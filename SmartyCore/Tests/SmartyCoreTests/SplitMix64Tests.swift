import SmartyCore
import Testing

struct SplitMix64Tests {
    @Test func matchesReferenceOutputForSeedZero() {
        var generator = SplitMix64(seed: 0)
        let outputs = (0..<3).map { _ in generator.next() }
        #expect(outputs == [0xE220_A839_7B1D_CDAF, 0x6E78_9E6A_A1B9_65F4, 0x06C4_5D18_8009_454F])
    }
}
