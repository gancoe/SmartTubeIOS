import Testing

@testable import SmartTubeIOSCore

@Suite("Native 4K HLS manifest filtering")
struct Native4KHLSManifestTests {

    @Test("4K VP9 profile 0 and H.264 survive with separate audio")
    func retainsSupported4KVideoCodecsAndAudio() {
        let manifest = """
            #EXTM3U
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="English - original",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE="en",URI="audio/original.m3u8"
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio",NAME="Spanish - dubbed",DEFAULT=NO,AUTOSELECT=YES,LANGUAGE="es",URI="audio/spanish.m3u8"
            #EXT-X-STREAM-INF:BANDWIDTH=18000000,RESOLUTION=3840x2160,CODECS="vp09.00.41.08,mp4a.40.2",AUDIO="audio"
            vp9-2160.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=16000000,RESOLUTION=3840x2160,CODECS="avc1.640033,mp4a.40.2",AUDIO="audio"
            h264-2160.m3u8
            """

        let filtered = filterHLSVariants(
            manifest,
            maximumHeight: 2160,
            allowedVideoCodecs: ["avc1", "vp09.00"]
        )

        #expect(filtered.contains("English - original"))
        #expect(filtered.contains("DEFAULT=YES"))
        #expect(filtered.contains("audio/original.m3u8"))
        #expect(filtered.contains("Spanish - dubbed"))
        #expect(filtered.contains("vp9-2160.m3u8"))
        #expect(filtered.contains("h264-2160.m3u8"))
    }

    @Test("variants above the maximum height are discarded")
    func discardsVariantsAboveMaximumHeight() {
        let manifest = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=30000000,RESOLUTION=7680x4320,CODECS="avc1.640033,mp4a.40.2"
            h264-4320.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=18000000,RESOLUTION=3840x2160,CODECS="vp09.00.41.08,mp4a.40.2"
            vp9-2160.m3u8
            """

        let filtered = filterHLSVariants(
            manifest,
            maximumHeight: 2160,
            allowedVideoCodecs: ["avc1", "vp09.00"]
        )

        #expect(!filtered.contains("h264-4320.m3u8"))
        #expect(filtered.contains("vp9-2160.m3u8"))
    }

    @Test("VP9 profile 2 and AV1 are rejected by the SDR whitelist")
    func rejectsUnsupportedProfilesAndCodecs() {
        let manifest = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=19000000,RESOLUTION=3840x2160,CODECS="vp09.02.51.10,mp4a.40.2"
            vp9-hdr-2160.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=17000000,RESOLUTION=3840x2160,CODECS="av01.0.12M.10,mp4a.40.2"
            av1-2160.m3u8
            """

        let filtered = filterHLSVariants(
            manifest,
            maximumHeight: 2160,
            allowedVideoCodecs: ["avc1", "vp09.00"]
        )

        #expect(!filtered.contains("vp9-hdr-2160.m3u8"))
        #expect(!filtered.contains("av1-2160.m3u8"))
    }

    @Test("legacy single-codec API keeps its H.264 behavior")
    func legacySingleCodecAPIStillWorks() {
        let manifest = """
            #EXTM3U
            #EXT-X-STREAM-INF:BANDWIDTH=16000000,RESOLUTION=3840x2160,CODECS="avc1.640033,mp4a.40.2"
            h264-2160.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=18000000,RESOLUTION=3840x2160,CODECS="vp09.00.41.08,mp4a.40.2"
            vp9-2160.m3u8
            """

        let filtered = filterHLSMasterManifest(
            manifest,
            maximumHeight: 2160,
            requiredVideoCodec: "avc1"
        )

        #expect(filtered.contains("h264-2160.m3u8"))
        #expect(!filtered.contains("vp9-2160.m3u8"))
    }

    @Test("empty, unknown, or missing CODECS values reject variants")
    func rejectsEmptyUnknownAndMissingCodecs() {
        let manifest = """
            #EXTM3U
            # a comment mentions avc1 but does not describe a video variant
            #EXT-X-STREAM-INF:BANDWIDTH=10000000,RESOLUTION=1920x1080,NAME="avc1 fallback",AUDIO="avc1",CODECS="zzzz.1,mp4a.40.2"
            avc1-in-unknown-name.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=9000000,RESOLUTION=1920x1080
            avc1-in-missing-codecs-name.m3u8
            #EXT-X-STREAM-INF:BANDWIDTH=8000000,RESOLUTION=1280x720,CODECS="avc1.640028,mp4a.40.2"
            allowed-720.m3u8
            """

        let empty = filterHLSVariants(
            manifest,
            maximumHeight: 2160,
            allowedVideoCodecs: []
        )
        let filtered = filterHLSVariants(
            manifest,
            maximumHeight: 2160,
            allowedVideoCodecs: ["avc1"]
        )

        #expect(!empty.contains("allowed-720.m3u8"))
        #expect(!filtered.contains("avc1-in-unknown-name.m3u8"))
        #expect(!filtered.contains("avc1-in-missing-codecs-name.m3u8"))
        #expect(filtered.contains("allowed-720.m3u8"))
    }
}
