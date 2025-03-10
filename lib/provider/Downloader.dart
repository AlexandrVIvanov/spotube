import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:queue/queue.dart';
import 'package:path/path.dart' as path;
import 'package:spotube/models/SpotubeTrack.dart';
import 'package:spotube/provider/UserPreferences.dart';
import 'package:spotube/provider/YouTube.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

Queue _queueInstance = Queue(delay: const Duration(seconds: 5));

class Downloader with ChangeNotifier {
  Queue _queue;
  YoutubeExplode yt;
  String downloadPath;
  FutureOr<bool> Function(SpotubeTrack track)? onFileExists;
  Downloader(
    this._queue, {
    required this.downloadPath,
    required this.yt,
    this.onFileExists,
  });

  int currentlyRunning = 0;
  Set<String> inQueue = {};

  void addToQueue(SpotubeTrack track) {
    if (inQueue.contains(track.id!)) return;
    currentlyRunning++;
    inQueue.add(track.id!);
    notifyListeners();
    _queue.add(() async {
      try {
        final file =
            File(path.join(downloadPath, '${track.ytTrack.title}.mp3'));
        if (file.existsSync() && await onFileExists?.call(track) != true) {
          return;
        }
        file.createSync(recursive: true);
        StreamManifest manifest =
            await yt.videos.streamsClient.getManifest(track.ytTrack.url);
        final audioStream = yt.videos.streamsClient
            .get(
              manifest.audioOnly
                  .where((audio) => audio.codec.mimeType == "audio/mp4")
                  .withHighestBitrate(),
            )
            .asBroadcastStream();

        IOSink outputFileStream = file.openWrite();
        await audioStream.pipe(outputFileStream);
        await outputFileStream.flush();
      } finally {
        currentlyRunning--;
        inQueue.remove(track.id);
        notifyListeners();
      }
    });
  }

  cancel() {
    _queue.cancel();
    _queueInstance = Queue();
    _queue = _queueInstance;
  }
}

final downloaderProvider = ChangeNotifierProvider(
  (ref) {
    return Downloader(
      _queueInstance,
      yt: ref.watch(youtubeProvider),
      downloadPath: ref.watch(
        userPreferencesProvider.select(
          (s) => s.downloadLocation,
        ),
      ),
    );
  },
);
