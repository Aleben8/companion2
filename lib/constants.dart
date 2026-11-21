import 'package:flutter/material.dart';

const int kBaseHp = 40;
const int kBaseEnergy = 15;
const int kStatMax = 15; // massimo per singola statistica
const int kStatPointsTotal = 30; // punti totali distribuibili
const int kInitialLife = 25;
const Color kDefaultColor = Color(0xFF0277BD);

const List<String> kTypes = [
  'Acciaio', 'Acqua', 'Buio', 'Coleottero', 'Drago', 'Elettro', 'Erba',
  'Folletto', 'Fuoco', 'Ghiaccio', 'Lotta', 'Normale', 'Psico', 'Roccia',
  'Spettro', 'Terra', 'Veleno', 'Volante',
];

/// Costo in energia di una mossa in base al suo "Dmg" (1-7).
int energyCostForDmg(int dmg) {
  switch (dmg) {
    case 1: return 1;
    case 2: return 2;
    case 3: return 4;
    case 4: return 7;
    case 5: return 9;
    case 6: return 10;
    case 7: return 11;
    default: return 99;
  }
}

/// Probabilità dell'effetto alterato: più la mossa è forte, meno è probabile.
double altStatusChanceForDmg(int dmg) {
  if (dmg >= 5) return 0;
  if (dmg == 4) return 0.2;
  if (dmg == 3) return 0.35;
  if (dmg == 2) return 0.5;
  return 0.8;
}

const Map<String, List<Color>> kTypeGradients = {
  'Fuoco': [Color(0xFFE5533D), Color(0xFFF29C38)],
  'Drago': [Color(0xFF1A237E), Color(0xFF6A1B9A)],
  'Acqua': [Color(0xFF1976D2), Color(0xFF4FC3F7)],
  'Erba': [Color(0xFF2E7D32), Color(0xFF9CCC65)],
  'Elettro': [Color(0xFFF9A825), Color(0xFFFFEE58)],
  'Ghiaccio': [Color(0xFF4DD0E1), Color(0xFFB2EBF2)],
  'Lotta': [Color(0xFFC62828), Color(0xFFFF8A65)],
  'Veleno': [Color(0xFF6A1B9A), Color(0xFFBA68C8)],
  'Terra': [Color(0xFF8D6E63), Color(0xFFD7B98E)],
  'Volante': [Color(0xFF7986CB), Color(0xFFB39DDB)],
  'Psico': [Color(0xFFD81B60), Color(0xFFF48FB1)],
  'Coleottero': [Color(0xFF689F38), Color(0xFFC0CA33)],
  'Roccia': [Color(0xFF8D8741), Color(0xFFBDB76B)],
  'Spettro': [Color(0xFF4527A0), Color(0xFF7E57C2)],
  'Buio': [Color(0xFF3E2723), Color(0xFF6D4C41)],
  'Acciaio': [Color(0xFF607D8B), Color(0xFFB0BEC5)],
  'Folletto': [Color(0xFFEC407A), Color(0xFFF8BBD0)],
  'Normale': [Color(0xFF757575), Color(0xFFBDBDBD)],
};

const Map<String, List<Color>> kStatGradients = {
  'Atk': [Color(0xFFE8574F), Color(0xFFF2C14E)],
  'AtkSpec': [Color(0xFFF2884B), Color(0xFFE0337A)],
  'Def': [Color(0xFF4FA3E8), Color(0xFF5BD6A0)],
  'DefSpec': [Color(0xFF7C5CE0), Color(0xFF4FA3E8)],
  'Vel': [Color(0xFFF2C14E), Color(0xFF5BD6A0)],
};

const Map<String, String> kStatLabels = {
  'Atk': 'Attacco',
  'AtkSpec': 'Attacco Spec.',
  'Def': 'Difesa',
  'DefSpec': 'Difesa Spec.',
  'Vel': 'Velocità',
};
