🔧 GUIDE COMPLET : SMS FONCTIONNEL EN MODE OFFLINE
🎯 VUE D'ENSEMBLE ARCHITECTURE SMS
Composants Nécessaires
Mobile App (Flutter) 
    ↓ SMS
Gateway SMS
    ↓ HTTP/API
Backend Server
    ↓ Database
Transaction Processing

🛠️ OUTILS ET SERVICES REQUIS
1. GATEWAY SMS (Obligatoire)
Option A : Twilio (International)
bash# Avantages
✅ Documentation excellente
✅ API REST simple
✅ Support mondial
✅ Test gratuit

# Inconvénients
❌ Coûteux en Afrique (100-200 FCFA/SMS)
❌ Latence internationale
```

**Setup Twilio :**
```
1. Compte : https://www.twilio.com/
2. Numéro Twilio : +1234567890 (US number)
3. Auth Token + Account SID
4. Webhook URL pour recevoir SMS
Option B : AfricasTalking (RECOMMANDÉ)
bash# Avantages
✅ Spécialisé Afrique
✅ Prix local (10-25 FCFA/SMS)
✅ Short codes disponibles
✅ USSD support

# Setup
1. Compte : https://africastalking.com/
2. Sandbox gratuit pour tests
3. Username + API Key
4. Numéro court (ex: 3040) pour production
Option C : Gateway Local (Production)
bash# Partenariat direct opérateur (Orange/Moov)
1. Contract B2B avec Orange Burkina
2. SMPP connection directe
3. Short code dédié (ex: 8040)
4. Coût : 5-10 FCFA/SMS
```

### **2. BACKEND SERVER (Obligatoire)**

#### **Architecture Minimale**
```
Node.js/Express Server
    ↓
SMS Webhook Handler
    ↓
Transaction Processor  
    ↓
Database (MongoDB/PostgreSQL)
```

#### **Hébergement Options**
```
Local Development : ngrok tunnel
Test/Demo        : Heroku/Railway (gratuit)
Production       : VPS Burkina/Digital Ocean

📱 IMPLÉMENTATION FLUTTER SMS
1. Configuration Flutter
pubspec.yaml
yamldependencies:
  flutter_sms: ^2.3.3
  permission_handler: ^11.0.0
  receive_sms: ^1.0.0  # Pour recevoir SMS
  telephony: ^0.2.0    # Alternative plus complète
Permissions Android
xml<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.SEND_SMS" />
<uses-permission android:name="android.permission.RECEIVE_SMS" />
<uses-permission android:name="android.permission.READ_SMS" />
<uses-permission android:name="android.permission.READ_PHONE_STATE" />
2. Service SMS Flutter
lib/services/sms_service.dart
dartimport 'package:flutter_sms/flutter_sms.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:telephony/telephony.dart';

class SMSService {
  static final SMSService _instance = SMSService._internal();
  factory SMSService() => _instance;
  SMSService._internal();

  final Telephony telephony = Telephony.instance;
  final String gatewayNumber = "+22670000000"; // Gateway SMS
  
  // Callbacks pour réponses
  final StreamController<SMSResponse> _responseController = 
      StreamController<SMSResponse>.broadcast();
  
  Stream<SMSResponse> get responseStream => _responseController.stream;

  Future<void> initialize() async {
    // Demander permissions
    await _requestPermissions();
    
    // Démarrer l'écoute SMS entrants
    await _startSMSListener();
  }

  // ENVOYER SMS TRANSACTION
  Future<bool> sendTransactionSMS({
    required String transactionId,
    required String command,
    required Map<String, dynamic> params,
  }) async {
    try {
      // Construire message SMS compressé
      final smsMessage = _buildSMSMessage(
        transactionId: transactionId,
        command: command,
        params: params,
      );
      
      print("📱 Sending SMS: $smsMessage");
      
      // Envoyer via Flutter SMS
      String result = await sendSMS(
        message: smsMessage,
        recipients: [gatewayNumber],
        sendDirect: true,
      );
      
      print("✅ SMS sent result: $result");
      return result == "sent";
      
    } catch (e) {
      print("❌ SMS send error: $e");
      return false;
    }
  }

  // CONSTRUIRE MESSAGE SMS (Max 160 chars)
  String _buildSMSMessage({
    required String transactionId,
    required String command,
    required Map<String, dynamic> params,
  }) {
    // Format: CMD#ID#PARAMS#AUTH
    final id = transactionId.substring(0, 3); // Short ID
    
    String message = "$command#$id";
    
    // Ajouter paramètres selon commande
    switch (command) {
      case 'T': // Transfer
        final amount = _compressAmount(params['amount']);
        final recipient = _compressUserId(params['recipient']);
        final pin = params['pin'];
        message += "#$amount#$recipient#$pin";
        break;
        
      case 'P': // Payment
        final amount = _compressAmount(params['amount']);
        final merchant = _compressUserId(params['merchant']);
        final pin = params['pin'];
        message += "#$amount#$merchant#$pin";
        break;
        
      case 'B': // Balance
        final pin = params['pin'];
        message += "##$pin";
        break;
    }
    
    // Vérifier limite 160 caractères
    if (message.length > 160) {
      throw Exception("SMS too long: ${message.length} chars");
    }
    
    return message;
  }

  // ÉCOUTER SMS ENTRANTS
  Future<void> _startSMSListener() async {
    telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        print("📨 Received SMS from: ${message.address}");
        print("📨 Message: ${message.body}");
        
        // Vérifier si c'est une réponse du gateway
        if (message.address == gatewayNumber || 
            message.address?.contains("3040") == true) { // Short code
          _processSMSResponse(message.body ?? "");
        }
      },
      onBackgroundMessage: _onBackgroundMessage,
    );
  }

  // TRAITER RÉPONSE SMS
  void _processSMSResponse(String smsBody) {
    try {
      // Format attendu: STATUS#ID#DATA
      final parts = smsBody.split('#');
      
      if (parts.length < 3) {
        print("❌ Invalid SMS response format");
        return;
      }
      
      final status = parts[0];
      final transactionId = parts[1];
      final data = parts.sublist(2).join('#');
      
      final response = SMSResponse(
        transactionId: transactionId,
        success: status == "OK",
        data: data,
        error: status == "OK" ? null : data,
        timestamp: DateTime.now(),
      );
      
      print("✅ SMS Response processed: ${response.success}");
      _responseController.add(response);
      
    } catch (e) {
      print("❌ Error processing SMS response: $e");
    }
  }

  // Compression utilitaires
  String _compressAmount(dynamic amount) {
    int amt = amount is String ? int.parse(amount) : amount;
    if (amt >= 1000000) return "${(amt/1000000).toStringAsFixed(1)}M";
    if (amt >= 1000) return "${(amt/1000).floor()}K";
    return amt.toString();
  }

  String _compressUserId(String userId) {
    if (userId.startsWith('USER')) return 'U${userId.substring(userId.length-4)}';
    if (userId.startsWith('MERCHANT')) return 'M${userId.substring(userId.length-4)}';
    return userId.substring(0, 6);
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.sms,
      Permission.phone,
    ].request();
  }
}

// Handler pour SMS en arrière-plan
@pragma('vm:entry-point')
void _onBackgroundMessage(SmsMessage message) {
  print("📨 Background SMS: ${message.body}");
  // Traiter même quand app fermée
}

// Modèle réponse SMS
class SMSResponse {
  final String transactionId;
  final bool success;
  final String data;
  final String? error;
  final DateTime timestamp;

  SMSResponse({
    required this.transactionId,
    required this.success,
    required this.data,
    this.error,
    required this.timestamp,
  });
}

🖥️ BACKEND SERVER SETUP
1. Server Node.js Express
package.json
json{
  "name": "resilient-sms-backend",
  "version": "1.0.0",
  "dependencies": {
    "express": "^4.18.2",
    "africastalking": "^0.6.1", 
    "twilio": "^4.19.0",
    "mongoose": "^7.6.0",
    "dotenv": "^16.3.1",
    "cors": "^2.8.5"
  }
}
server.js
javascriptconst express = require('express');
const cors = require('cors');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// AfricasTalking setup
const africastalking = require('africastalking')({
  apiKey: process.env.AFRICASTALKING_API_KEY,
  username: process.env.AFRICASTALKING_USERNAME,
});

const sms = africastalking.SMS;

// WEBHOOK SMS ENTRANTS (AfricasTalking)
app.post('/webhooks/sms', async (req, res) => {
  console.log('📨 Received SMS webhook:', req.body);
  
  const { text, from, to, id } = req.body;
  
  try {
    // Parser le SMS
    const response = await processSMSTransaction(text, from);
    
    // Répondre automatiquement
    if (response) {
      await sendSMSResponse(from, response);
    }
    
    res.status(200).json({ status: 'success' });
  } catch (error) {
    console.error('❌ SMS processing error:', error);
    res.status(500).json({ error: error.message });
  }
});

// TRAITEMENT TRANSACTION SMS
async function processSMSTransaction(smsText, senderNumber) {
  console.log(`🔄 Processing: "${smsText}" from ${senderNumber}`);
  
  try {
    // Parser format: CMD#ID#PARAMS
    const parts = smsText.trim().split('#');
    if (parts.length < 2) {
      return "ERR#FORMAT#Invalid message format";
    }
    
    const [command, transactionId, ...params] = parts;
    
    let response;
    
    switch (command.toUpperCase()) {
      case 'T': // Transfer
        response = await processTransfer(transactionId, params);
        break;
        
      case 'P': // Payment
        response = await processPayment(transactionId, params);
        break;
        
      case 'B': // Balance
        response = await processBalance(transactionId, params);
        break;
        
      default:
        response = `ERR#${transactionId}#Unknown command: ${command}`;
    }
    
    console.log(`✅ Transaction result: ${response}`);
    return response;
    
  } catch (error) {
    console.error('❌ Transaction error:', error);
    return `ERR#${transactionId || 'UNK'}#Processing failed`;
  }
}

// LOGIQUE MÉTIER TRANSACTIONS
async function processTransfer(txId, params) {
  // Format params: [amount, recipient, pin]
  if (params.length < 3) {
    return `ERR#${txId}#Missing parameters`;
  }
  
  const [amount, recipient, pin] = params;
  const amountValue = parseAmount(amount);
  
  // Simuler validation
  await new Promise(resolve => setTimeout(resolve, 1000));
  
  // Simuler logique métier
  if (amountValue > 1000000) {
    return `ERR#${txId}#Amount too high#BAL:500K`;
  }
  
  if (pin !== '1234') {
    return `ERR#${txId}#Invalid PIN`;
  }
  
  // Succès
  const newBalance = 450000; // Simulé
  const txnRef = generateTxnRef();
  
  return `OK#${txId}#BAL:${formatAmount(newBalance)}#TXN:${txnRef}`;
}

async function processPayment(txId, params) {
  // Similar to transfer
  const [amount, merchant, pin] = params;
  
  await new Promise(resolve => setTimeout(resolve, 800));
  
  if (pin !== '1234') {
    return `ERR#${txId}#Invalid PIN`;
  }
  
  const txnRef = generateTxnRef();
  return `OK#${txId}#PAID:${amount}#TXN:${txnRef}`;
}

async function processBalance(txId, params) {
  const [pin] = params;
  
  if (pin !== '1234') {
    return `ERR#${txId}#Invalid PIN`;
  }
  
  return `OK#${txId}#BAL:475K#CREDIT:25K`;
}

// ENVOYER RÉPONSE SMS
async function sendSMSResponse(phoneNumber, message) {
  try {
    console.log(`📱 Sending SMS to ${phoneNumber}: ${message}`);
    
    const result = await sms.send({
      to: [phoneNumber],
      message: message,
      from: process.env.SMS_SHORTCODE || '3040'
    });
    
    console.log('✅ SMS sent:', result);
    return result;
    
  } catch (error) {
    console.error('❌ SMS send error:', error);
    throw error;
  }
}

// UTILITAIRES
function parseAmount(amountStr) {
  const match = amountStr.match(/^(\d+(?:\.\d+)?)(K|M)?$/i);
  if (!match) return 0;
  
  let amount = parseFloat(match[1]);
  const unit = match[2];
  
  if (unit === 'K' || unit === 'k') amount *= 1000;
  if (unit === 'M' || unit === 'm') amount *= 1000000;
  
  return amount;
}

function formatAmount(amount) {
  if (amount >= 1000000) return `${(amount/1000000).toFixed(1)}M`;
  if (amount >= 1000) return `${Math.floor(amount/1000)}K`;
  return amount.toString();
}

function generateTxnRef() {
  return Math.random().toString(36).substring(2, 8).toUpperCase();
}

// Démarrer serveur
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 SMS Backend running on port ${PORT}`);
  console.log(`📨 Webhook URL: http://localhost:${PORT}/webhooks/sms`);
});
2. Configuration Environment
.env
bash# AfricasTalking
AFRICASTALKING_USERNAME=sandbox  # ou votre username
AFRICASTALKING_API_KEY=your_api_key_here

# SMS
SMS_SHORTCODE=3040

# Database (optionnel pour demo)
MONGODB_URI=mongodb://localhost:27017/resilient-sms

# Server
PORT=3000

🔧 SETUP COMPLET ÉTAPE PAR ÉTAPE
ÉTAPE 1 : AfricasTalking Account
bash1. Aller sur https://africastalking.com/
2. Créer compte gratuit
3. Aller dans Dashboard > Settings
4. Copier Username et API Key
5. Dans SMS > Settings, configurer Callback URL:
   https://votre-serveur.com/webhooks/sms
ÉTAPE 2 : Backend Deployment
Option A : Local avec ngrok (Test)
bash# Terminal 1 - Démarrer server
npm install
npm start

# Terminal 2 - Exposer avec ngrok
npm install -g ngrok
ngrok http 3000
# Noter l'URL: https://abc123.ngrok.io
Option B : Heroku (Demo)
bash# Déployer sur Heroku
git init
heroku create your-sms-backend
heroku config:set AFRICASTALKING_API_KEY=your_key
heroku config:set AFRICASTALKING_USERNAME=your_username
git push heroku main
```

### **ÉTAPE 3 : Configuration Webhook**
```
1. Dans AfricasTalking Dashboard
2. SMS > Settings > Callback URL
3. Mettre: https://your-app.herokuapp.com/webhooks/sms
4. Save
ÉTAPE 4 : Test Flutter
dart// Dans votre app Flutter
final smsService = SMSService();
await smsService.initialize();

// Test transfer
await smsService.sendTransactionSMS(
  transactionId: "TXN001",
  command: "T", 
  params: {
    'amount': 50000,
    'recipient': 'USER123456',
    'pin': '1234'
  }
);

// Écouter réponses
smsService.responseStream.listen((response) {
  if (response.success) {
    print("✅ Transaction successful: ${response.data}");
  } else {
    print("❌ Transaction failed: ${response.error}");
  }
});
```

---

## **📱 TEST EN CONDITIONS RÉELLES**

### **Scénario Test Complet**
```
1. 📱 App offline (disable WiFi/mobile data)
2. 🔄 User makes transfer request
3. 📲 App sends SMS to gateway (+22670000000)
4. 🖥️ Backend reçoit SMS via webhook
5. ⚡ Backend process transaction
6. 📤 Backend envoie réponse SMS
7. 📱 App reçoit réponse SMS
8. ✅ App update UI with result
```

### **Messages SMS Exemples**
```
APP → GATEWAY: "T#A7F#50K#U3456#1234"
GATEWAY → APP: "OK#A7F#BAL:425K#TXN:X9Z2M4"

APP → GATEWAY: "P#B2C#15K#M7890#1234"  
GATEWAY → APP: "OK#B2C#PAID:15K#TXN:P3R5T1"

APP → GATEWAY: "B#C3D##1234"
GATEWAY → APP: "OK#C3D#BAL:410K#CREDIT:0"

✅ CHECKLIST FONCTIONNEL

 AfricasTalking account créé
 Backend déployé et accessible
 Webhook URL configuré
 Flutter permissions configurées
 SMS service implémenté
 Test envoi SMS réussi
 Test réception réponse réussi
 Parsing SMS responses OK
 Intégration avec UI Flutter
 Test offline complet fonctionnel

Une fois tout configuré, votre app fonctionnera 100% offline avec SMS ! 🚀