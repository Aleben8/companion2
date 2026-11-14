import 'package:firebase_core/firebase_core.dart';

/// Configurazione Firebase recuperata dalla build web originale.
/// (Le chiavi web di Firebase non sono segrete: la sicurezza è nelle regole Firestore.)
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform => web;

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyA03HEe8bJV9NRVWjFcI7qAOW4cZdNCT74',
    appId: '1:559844228956:web:98a949644db3ceead34b99',
    messagingSenderId: '559844228956',
    projectId: 'pokemoncompanion-cc8dc',
    authDomain: 'pokemoncompanion-cc8dc.firebaseapp.com',
    databaseURL:
        'https://pokemoncompanion-cc8dc-default-rtdb.europe-west1.firebasedatabase.app',
    storageBucket: 'pokemoncompanion-cc8dc.firebasestorage.app',
  );
}
