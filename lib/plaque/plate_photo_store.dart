// PARKFASO — Politique de conservation des photos de plaques.
//
// Par défaut : la photo est supprimée dès que le numéro est enregistré.
// Si le propriétaire active la conservation :
//   • stockage dans le dossier privé de l'application (inaccessible aux autres
//     applis, absent de la galerie grâce au fichier .nomedia) ;
//   • suppression automatique après N jours ;
//   • consultation réservée aux rôles autorisés (voir [canView]).

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PlatePhotoStore {
  PlatePhotoStore({
    required this.keepPhotos,
    required this.retentionDays,
    this.allowedRoles = const {'proprietaire', 'admin'},
    Future<Directory> Function()? baseDir,
  }) : _baseDir = baseDir ?? getApplicationSupportDirectory;

  final bool keepPhotos;
  final int retentionDays;
  final Set<String> allowedRoles;
  final Future<Directory> Function() _baseDir;

  Future<Directory> _dir() async {
    final d = Directory(p.join((await _baseDir()).path, 'plaques'));
    if (!d.existsSync()) {
      d.createSync(recursive: true);
      File(p.join(d.path, '.nomedia')).writeAsStringSync('');
    }
    return d;
  }

  /// Appelé après l'enregistrement. Retourne le chemin conservé, ou null si la
  /// photo a été supprimée (comportement par défaut).
  Future<String?> finalize(String? tempPhotoPath, {required String ticketBase}) async {
    if (tempPhotoPath == null) return null;
    final src = File(tempPhotoPath);
    if (!src.existsSync()) return null;
    if (!keepPhotos) {
      await _safeDelete(src);
      return null;
    }
    final dest = File(p.join((await _dir()).path, '${ticketBase}_${DateTime.now().millisecondsSinceEpoch}.jpg'));
    try {
      await src.rename(dest.path);
    } on FileSystemException {
      await src.copy(dest.path);
      await _safeDelete(src);
    }
    return dest.path;
  }

  /// Supprime une photo capturée mais abandonnée (gardien qui annule).
  Future<void> discard(String? tempPhotoPath) async {
    if (tempPhotoPath != null) await _safeDelete(File(tempPhotoPath));
  }

  /// Supprime les photos plus anciennes que la durée de rétention.
  /// À appeler au démarrage de l'application. Retourne le nombre supprimé.
  Future<int> purgeExpired({DateTime? now}) async {
    final d = await _dir();
    final limit = (now ?? DateTime.now()).subtract(Duration(days: retentionDays));
    var n = 0;
    for (final f in d.listSync().whereType<File>()) {
      if (p.basename(f.path) == '.nomedia') continue;
      if (!keepPhotos || f.lastModifiedSync().isBefore(limit)) {
        await _safeDelete(f);
        n++;
      }
    }
    return n;
  }

  /// Contrôle d'accès à la consultation des photos.
  bool canView(String role) => keepPhotos && allowedRoles.contains(role.toLowerCase());

  Future<void> _safeDelete(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}
