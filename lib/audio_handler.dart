import 'package:audio_service/audio_service.dart';

import 'playback.dart';

/// Connects the player to the Android media notification and lock screen controls.
class MediaXAudioHandler extends BaseAudioHandler with SeekHandler {
  MediaXAudioHandler() {
    final pb = Playback.instance;
    pb.player.stream.playing.listen((_) => _broadcast());
    pb.player.stream.position.listen((_) => _broadcast());
    pb.player.stream.duration.listen((_) => _publishItem());
    pb.addListener(_publishItem);
  }

  void _publishItem() {
    final pb = Playback.instance;
    final c = pb.current;
    if (c == null) {
      mediaItem.add(null);
    } else {
      final dur = pb.player.state.duration;
      mediaItem.add(MediaItem(
        id: c.url,
        title: c.title,
        artist: c.subtitle,
        duration: dur == Duration.zero ? null : dur,
      ));
    }
    _broadcast();
  }

  void _broadcast() {
    final pb = Playback.instance;
    final playing = pb.player.state.playing;
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.skipToNext,
        MediaControl.stop,
      ],
      systemActions: const {MediaAction.seek},
      androidCompactActionIndices: const [0, 1, 2],
      processingState: pb.current == null ? AudioProcessingState.idle : AudioProcessingState.ready,
      playing: playing,
      updatePosition: pb.player.state.position,
      speed: pb.player.state.rate,
    ));
  }

  @override
  Future<void> play() async => Playback.instance.player.play();

  @override
  Future<void> pause() async => Playback.instance.player.pause();

  @override
  Future<void> seek(Duration position) async => Playback.instance.player.seek(position);

  @override
  Future<void> skipToNext() async => Playback.instance.next();

  @override
  Future<void> skipToPrevious() async => Playback.instance.prev();

  @override
  Future<void> stop() async {
    Playback.instance.stop();
    await super.stop();
  }
}
