import 'package:firebase_storage/firebase_storage.dart';
import 'constant.dart';

class FirebaseStorageHelper {
  FirebaseStorageHelper._();

  static Iterable<FirebaseStorage> storageCandidates() {
    final configured = _normalizeBucket(firebaseStorageBucket);
    final buckets = <String>{};

    if (configured.isNotEmpty) {
      buckets.add(configured);
      if (configured.endsWith('.firebasestorage.app')) {
        buckets.add(
          configured.replaceFirst('.firebasestorage.app', '.appspot.com'),
        );
      } else if (configured.endsWith('.appspot.com')) {
        buckets.add(
          configured.replaceFirst('.appspot.com', '.firebasestorage.app'),
        );
      }
    }

    // Keep default instance as a fallback candidate too.
    return [
      for (final bucket in buckets) FirebaseStorage.instanceFor(bucket: 'gs://$bucket'),
      FirebaseStorage.instance,
    ];
  }

  static bool isBucketNotFoundError(Object error) {
    final message = error.toString().toLowerCase();
    if (error is FirebaseException && error.code == 'bucket-not-found') {
      return true;
    }
    return message.contains('bucket not found') ||
        message.contains('bucket-not-found');
  }

  static String _normalizeBucket(String value) {
    var bucket = value.trim();
    if (bucket.startsWith('gs://')) {
      bucket = bucket.substring(5);
    }
    return bucket;
  }
}