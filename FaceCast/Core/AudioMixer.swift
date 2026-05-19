import CoreMedia

/// Mixes the microphone and system-audio streams into a single audio track.
final class AudioMixer {
    var microphoneGain: Float = 1.0
    var systemAudioGain: Float = 1.0

    /// Mixes the two optional sources. Currently returns one of them unchanged.
    func mix(microphone: CMSampleBuffer?, system: CMSampleBuffer?) -> CMSampleBuffer? {
        // TODO: resample both sources to a common format and mix the PCM samples.
        return microphone ?? system
    }
}
