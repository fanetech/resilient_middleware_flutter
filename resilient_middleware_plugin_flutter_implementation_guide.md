# **RESILIENT MIDDLEWARE FLUTTER PLUGIN - IMPLEMENTATION GUIDE**

## **PROJECT OVERVIEW**
Create a Flutter plugin called `resilient_middleware` that automatically handles network failures by implementing a triple-channel communication system: Internet → Local Queue → SMS Fallback. The plugin should work transparently - developers just import it and their app becomes resilient to network failures.

## **CORE REQUIREMENTS**

### **Main Features**
1. **Automatic network detection** and quality assessment
2. **Local queue management** with SQLite for offline requests
3. **SMS fallback** when internet is unavailable for critical transactions
4. **Automatic retry** with exponential backoff
5. **Zero-config integration** - works with one line of code

### **Technical Stack**
- Flutter/Dart for the plugin
- SQLite for local persistence
- Native SMS integration (Android first, iOS later)
- HTTP for network requests
- SMS compression protocol for 160 character limit

---

## **STEP-BY-STEP IMPLEMENTATION**

### **STEP 1: Project Setup**

#### **1.1 Create Plugin Structure**
```bash
flutter create --template=plugin resilient_middleware
cd resilient_middleware
```

#### **1.2 Add Dependencies**
Add these dependencies to `pubspec.yaml`:
```yaml
dependencies:
  flutter:
    sdk: flutter
  connectivity_plus: ^4.0.0
  sqflite: ^2.3.0
  http: ^1.1.0
  shared_preferences: ^2.2.0
  permission_handler: ^11.0.0
  flutter_sms: ^2.3.3
  crypto: ^3.0.3
  path: ^1.8.3

dev_dependencies:
  flutter_test:
    sdk: flutter
  mockito: ^5.4.0
  flutter_lints: ^2.0.0
```

#### **1.3 Create Folder Structure**
```
lib/
├── src/
│   ├── core/
│   │   ├── network_detector.dart
│   │   ├── queue_manager.dart
│   │   ├── sms_gateway.dart
│   │   └── resilient_api.dart
│   ├── models/
│   │   ├── request_model.dart
│   │   ├── response_model.dart
│   │   └── queue_item.dart
│   ├── utils/
│   │   ├── sms_compressor.dart
│   │   └── logger.dart
│   └── database/
│       └── offline_database.dart
└── resilient_middleware.dart (main entry point)
```

---

### **STEP 2: Network Detector Implementation**

#### **2.1 Create `network_detector.dart`**

**Features to Implement:**
- Real-time connectivity monitoring using `connectivity_plus`
- Network quality scoring (0-1) based on:
  - Connection type (WiFi=1.0, 4G=0.8, 3G=0.5, 2G=0.3)
  - Latency tests (ping to reliable server)
  - Recent success/failure history
- Stream-based updates for network changes

**Core Methods:**
```dart
class NetworkDetector {
  Stream<NetworkStatus> get networkStream;
  Future<double> getNetworkScore();
  Future<bool> isStable();
  Future<NetworkType> getNetworkType();
  Future<int> measureLatency();
}
```

**Network Quality Scoring Algorithm:**
- WiFi: Base score 1.0
- Mobile 4G: Base score 0.8
- Mobile 3G: Base score 0.5
- Mobile 2G: Base score 0.3
- Adjust based on latency: <100ms (+0.1), >1000ms (-0.2)
- Factor in recent failures: Each failure in last 5 min reduces score by 0.1

---

### **STEP 3: Queue Manager with SQLite**

#### **3.1 Database Schema**

Create `offline_database.dart` with schema:
```sql
CREATE TABLE request_queue (
  id TEXT PRIMARY KEY,
  method TEXT NOT NULL,
  url TEXT NOT NULL,
  headers TEXT,
  body TEXT,
  priority INTEGER DEFAULT 5,
  retry_count INTEGER DEFAULT 0,
  max_retries INTEGER DEFAULT 3,
  created_at INTEGER NOT NULL,
  expires_at INTEGER,
  status TEXT DEFAULT 'pending',
  idempotency_key TEXT UNIQUE,
  sms_eligible INTEGER DEFAULT 0
);

CREATE INDEX idx_priority_created 
ON request_queue(priority DESC, created_at ASC);

CREATE INDEX idx_status 
ON request_queue(status);
```

#### **3.2 Queue Manager Features**

**Core Methods:**
```dart
class QueueManager {
  Future<String> enqueue(QueuedRequest request);
  Future<QueuedRequest?> dequeue();
  Future<List<QueuedRequest>> getPendingRequests(int limit);
  Future<void> updateStatus(String id, String status);
  Future<void> incrementRetryCount(String id);
  Future<void> processQueue();
  Future<void> cleanExpiredRequests();
}
```

**Priority Levels:**
- 10: CRITICAL (medical, emergency)
- 8: HIGH (payments, transfers)
- 5: NORMAL (updates, posts)
- 3: LOW (analytics, logs)

**Retry Strategy:**
- Exponential backoff: 1s, 2s, 4s, 8s, 16s...
- Max retries: 3 for normal, 5 for high priority
- After max retries: Mark for SMS if eligible

---

### **STEP 4: SMS Gateway Integration**

#### **4.1 SMS Protocol Format**

**Message Structure:** `[CMD]#[ID]#[PARAMS]#[AUTH]`
- Maximum 160 characters
- Use # as separator (more reliable than comma)

**Command Dictionary:**
```
T = Transfer
P = Payment
B = Balance
D = Deposit
W = Withdrawal
V = Verify
```

#### **4.2 Compression Rules**

**Amount Compression:**
- 1000 → 1K
- 50000 → 50K
- 1500000 → 1.5M

**User ID Compression:**
- Take last 4-6 significant digits
- USER123456 → U3456
- MERCHANT789012 → M9012

#### **4.3 SMS Gateway Implementation**

```dart
class SMSGateway {
  static const String GATEWAY_NUMBER = "+22670000000";
  
  Future<bool> sendSMS(QueuedRequest request);
  String compressRequest(QueuedRequest request);
  Response parseResponse(String smsBody);
  Future<bool> requestPermissions();
  Stream<String> listenForResponses();
}
```

**Example Messages:**
- Transfer: `T#A7F#50K#U4567#1234`
- Payment: `P#B2C#15K#FACT789#5678`
- Balance: `B#C3D##9012`

**Response Format:**
- Success: `OK#[ID]#BAL:45K#TXN:789456`
- Error: `ERR#[ID]#INSUFFICIENT#BAL:2K`

---

### **STEP 5: Main Resilient API**

#### **5.1 Core API Structure**

```dart
class ResilientMiddleware {
  // Singleton initialization
  static Future<void> initialize({
    String? smsGateway,
    bool enableSMS = true,
    Duration timeout = const Duration(seconds: 30),
    SMSCostProvider? costProvider,
  });
  
  // Main execution method
  Future<Response> execute(Request request);
  
  // Configuration methods
  void setStrategy(ResilienceStrategy strategy);
  void setSMSThreshold(Duration duration);
  void setMaxQueueSize(int size);
}
```

#### **5.2 Decision Flow Algorithm**

```
START
  ↓
Check Network Score
  ↓
Score > 0.7? → Try HTTP (30s timeout)
  ↓ No
Score > 0.3? → Try HTTP (5s timeout)
  ↓ No
Is Urgent? → Send SMS Immediately
  ↓ No
Queue Request
  ↓
Wait 5 minutes
  ↓
Still Offline? → Propose SMS
  ↓
END
```

#### **5.3 Resilience Strategies**

**AGGRESSIVE:** Always try network first, quick SMS fallback
**BALANCED:** Smart detection, 5 min wait before SMS
**CONSERVATIVE:** Minimize SMS usage, long waits
**CUSTOM:** User-defined rules

---

### **STEP 6: Native Android SMS Implementation**

#### **6.1 Android Manifest Permissions**

Add to `android/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.SEND_SMS" />
<uses-permission android:name="android.permission.RECEIVE_SMS" />
<uses-permission android:name="android.permission.READ_SMS" />
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
```

#### **6.2 Kotlin SMS Bridge**

Create `android/src/main/kotlin/.../SmsBridge.kt`:

```kotlin
class SmsBridge(private val context: Context) : MethodCallHandler {
  
  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "sendSMS" -> sendSMS(call, result)
      "listenSMS" -> setupSMSListener(result)
      else -> result.notImplemented()
    }
  }
  
  private fun sendSMS(call: MethodCall, result: Result) {
    val number = call.argument<String>("number")
    val message = call.argument<String>("message")
    
    val smsManager = SmsManager.getDefault()
    smsManager.sendTextMessage(number, null, message, null, null)
    result.success(true)
  }
}
```

#### **6.3 SMS Broadcast Receiver**

Implement receiver for incoming SMS responses from the gateway.

---

### **STEP 7: Simple Integration API**

#### **7.1 One-Line Setup**

```dart
// In main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // One-line initialization
  await ResilientMiddleware.initialize(
    smsGateway: '+22670000000',
    enableSMS: true,
  );
  
  runApp(MyApp());
}
```

#### **7.2 Drop-in HTTP Replacement**

```dart
// Instead of http.post()
final response = await ResilientHttp.post(
  'https://api.example.com/transfer',
  body: {'amount': 5000, 'recipient': 'USER123'},
  priority: Priority.HIGH,
);

// Automatic handling:
// - Queues if offline
// - Retries with backoff
// - Falls back to SMS if urgent
// - Returns same Response type
```

#### **7.3 Advanced Configuration**

```dart
ResilientMiddleware.configure(
  strategy: ResilienceStrategy.AGGRESSIVE,
  smsTimeout: Duration(minutes: 3),
  smsCostWarning: true,
  batchSMS: true,
  maxQueueSize: 1000,
);
```

---

### **STEP 8: Testing Suite**

#### **8.1 Unit Tests**

**Test Coverage Requirements:**
- Network detection accuracy: >95%
- Queue persistence: 100%
- SMS compression/decompression: 100%
- Retry logic: All edge cases
- Priority ordering: Correct sequence
- Idempotency: No duplicates

#### **8.2 Test Scenarios**

```dart
// Test files to create:
test/
├── network_detector_test.dart
├── queue_manager_test.dart
├── sms_gateway_test.dart
├── resilient_api_test.dart
└── integration_test.dart
```

**Critical Test Cases:**
1. Online → Offline → Online transition
2. Urgent request while offline → SMS immediate
3. Queue 100 requests → Verify priority order
4. App crash → Restart → Queue intact
5. SMS fallback timing
6. Idempotency key uniqueness
7. Expired request cleanup
8. Network score accuracy

#### **8.3 Integration Tests**

```dart
testWidgets('Full offline-online cycle', (tester) async {
  // 1. Start online, make request
  // 2. Go offline, make request
  // 3. Verify queued
  // 4. Go online
  // 5. Verify processed
});
```

---

### **STEP 9: Example App**

#### **9.1 Banking Demo App Structure**

```
example/
├── lib/
│   ├── main.dart
│   ├── screens/
│   │   ├── home_screen.dart
│   │   ├── transfer_screen.dart
│   │   └── history_screen.dart
│   └── widgets/
│       ├── network_indicator.dart
│       ├── queue_badge.dart
│       └── sms_cost_dialog.dart
```

#### **9.2 Key Features to Demonstrate**

1. **Network Status Indicator**
   - Green: Online (excellent)
   - Yellow: Online (poor)
   - Red: Offline
   - Shows queue count badge

2. **Transfer Money Screen**
   - Amount input
   - Recipient selection
   - Priority selector
   - "Send" button
   - Cost warning if SMS

3. **Queue Management**
   - List of pending transactions
   - Retry option
   - Cancel option
   - Priority change

4. **SMS Cost Calculator**
   - Shows estimated cost
   - Daily/Monthly totals
   - Cost optimization tips

---

### **STEP 10: Documentation**

#### **10.1 README.md Structure**

```markdown
# Resilient Middleware

## Quick Start (3 lines)
\```dart
await ResilientMiddleware.initialize(smsGateway: '+22670000000');
// Now all HTTP requests are resilient!
final response = await ResilientHttp.get('https://api.example.com/data');
\```

## Features
- ✅ Automatic offline detection
- ✅ Smart queue management
- ✅ SMS fallback for critical operations
- ✅ Zero configuration needed
- ✅ Works with existing HTTP code

## Installation
\```yaml
dependencies:
  resilient_middleware: ^1.0.0
\```

## Configuration Options
- SMS Gateway setup
- Priority levels
- Retry strategies
- Cost management

## API Documentation
[Link to full API docs]

## Examples
[Link to example app]

## Troubleshooting
[Common issues and solutions]
```

#### **10.2 API Documentation**

Generate with dartdoc:
```bash
dartdoc --output=docs
```

Key sections:
- Getting Started
- Core Concepts
- Configuration
- SMS Protocol
- Best Practices
- FAQ

---

## **DELIVERABLES CHECKLIST**

- [ ] **Working Flutter plugin** with all core features
- [ ] **Example banking app** demonstrating usage
- [ ] **Unit tests** with >80% coverage
- [ ] **Integration tests** for critical flows
- [ ] **README.md** with clear setup instructions
- [ ] **API documentation** (dartdoc generated)
- [ ] **CHANGELOG.md** with version history
- [ ] **LICENSE** file (MIT recommended)
- [ ] **pubspec.yaml** properly configured
- [ ] **CI/CD** setup (GitHub Actions)

---

## **SUCCESS CRITERIA**

- [ ] **Zero data loss** when offline
- [ ] **SMS fallback** activates in <5 seconds
- [ ] **Queue survives** app restart/crash
- [ ] **Package size** <2MB
- [ ] **Integration time** <5 minutes
- [ ] **Android 5.0+** support
- [ ] **Flutter 3.0+** compatible
- [ ] **Null safety** enabled
- [ ] **pub.dev score** >130/140

---

## **BONUS FEATURES** (If Time Permits)

### **Advanced Features**
1. **Batch SMS** - Combine multiple requests in one SMS
2. **Predictive offline** - Learn user patterns and pre-queue
3. **Cost calculator** - Real-time SMS cost estimation
4. **Analytics dashboard** - Success rates, costs, patterns
5. **Web dashboard** - Monitor all app instances remotely
6. **Compression AI** - Smart compression based on content
7. **Multi-gateway** - Support multiple SMS providers
8. **E2E encryption** - Secure SMS communication
9. **GraphQL support** - Not just REST
10. **WebSocket resilience** - Handle real-time connections

---

## **DEVELOPMENT TIMELINE**

### **Week 1: Core Components**
- Day 1-2: Project setup, network detector
- Day 3-4: Queue manager, database
- Day 5: SMS gateway basic implementation

### **Week 2: Integration**
- Day 6-7: Resilient API, decision engine
- Day 8-9: Native Android SMS bridge
- Day 10: Testing framework setup

### **Week 3: Polish & Release**
- Day 11-12: Example app
- Day 13: Documentation
- Day 14: Testing & bug fixes
- Day 15: Publish to pub.dev

---

## **GETTING STARTED**

```bash
# Clone the repository
git clone https://github.com/yourusername/resilient_middleware.git

# Install dependencies
flutter pub get

# Run tests
flutter test

# Run example app
cd example
flutter run
```

---

## **SUPPORT & CONTRIBUTION**

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Email**: support@resilientmiddleware.dev
- **Contributing**: See CONTRIBUTING.md

---

**Remember:** The goal is to make ANY Flutter app resilient with just one import. Every decision should prioritize simplicity for the end developer while handling all complexity internally.

**Focus:** Start with Android SMS, iOS can be added in v2.0. Get a working prototype first, then optimize.
