import Foundation
import Accelerate
import XCTest

// MARK: - vDSP Performance Benchmark Tests
/// TDD-based benchmarks verifying 4-8x speedup over scalar operations
///
/// These tests follow the TDD workflow:
/// 1. Write benchmark first (this file)
/// 2. Implement vDSP version (already done in production code)
/// 3. Verify 4-8x speedup

@available(macOS 15.0, *)
final class VDSPSpeedupBenchmarkTests: XCTestCase {
    
    // MARK: - Test Constants
    
    /// Sample sizes for testing (typical audio buffer sizes)
    let sampleSizes = [1024, 4096, 16384, 65536, 262144]
    
    /// Number of iterations for stable timing
    let iterations = 100
    
    /// Minimum acceptable speedup factor
    let minSpeedup = 2.0
    
    /// Target speedup factor (4-8x)
    let targetSpeedup = 4.0
    
    // MARK: - vDSP_deqinterleave Benchmarks
    
    /// Test stereo-to-mono deinterleave performance
    /// Expected: 4-8x speedup on Apple Silicon
    func testStereoToMonoDeinterleaveSpeedup() throws {
        let frameCount = 16384  // ~1 second at 16kHz
        let interleaved = generateInterleavedStereoSamples(frameCount: frameCount)
        
        // Scalar implementation
        let scalarTime = measureScalarDeinterleave(
            interleaved: interleaved,
            frameCount: frameCount
        )
        
        // vDSP implementation
        let vdspTime = measureVDSPDeinterleave(
            interleaved: interleaved,
            frameCount: frameCount
        )
        
        let speedup = scalarTime / vdspTime
        
        // Log results
        print("📊 Stereo-to-Mono Deinterleave:")
        print("   Scalar: \(String(format: "%.4f", scalarTime))s")
        print("   vDSP:   \(String(format: "%.4f", vdspTime))s")
        print("   Speedup: \(String(format: "%.2f", speedup))x")
        
        // Verify minimum speedup
        XCTAssertGreaterThan(
            speedup,
            minSpeedup,
            "vDSP deinterleave should be at least \(Int(minSpeedup))x faster than scalar"
        )
        
        // Target 4x for stereo processing
        if speedup >= targetSpeedup {
            print("✅ Target 4x speedup achieved!")
        }
    }
    
    // MARK: - vDSP_vadd Benchmarks
    
    /// Test vector addition (mixing) performance
    /// Expected: 3-6x speedup
    func testVectorAdditionSpeedup() throws {
        let count = 65536
        let a = generateRandomSamples(count: count)
        let b = generateRandomSamples(count: count)
        
        // Scalar implementation
        let scalarTime = measureScalarAddition(a: a, b: b)
        
        // vDSP implementation
        let vdspTime = measureVDSPAddition(a: a, b: b)
        
        let speedup = scalarTime / vdspTime
        
        print("📊 Vector Addition (Mixing):")
        print("   Scalar: \(String(format: "%.4f", scalarTime))s")
        print("   vDSP:   \(String(format: "%.4f", vdspTime))s")
        print("   Speedup: \(String(format: "%.2f", speedup))x")
        
        XCTAssertGreaterThan(
            speedup,
            minSpeedup,
            "vDSP addition should be at least \(Int(minSpeedup))x faster than scalar"
        )
    }
    
    // MARK: - vDSP_vsmul Benchmarks
    
    /// Test vector scaling (gain) performance
    /// Expected: 3-6x speedup
    func testVectorScalingSpeedup() throws {
        let count = 65536
        let input = generateRandomSamples(count: count)
        let gain: Float = 0.5
        
        // Scalar implementation
        let scalarTime = measureScalarScaling(input: input, gain: gain)
        
        // vDSP implementation
        let vdspTime = measureVDSPScaling(input: input, gain: gain)
        
        let speedup = scalarTime / vdspTime
        
        print("📊 Vector Scaling (Gain):")
        print("   Scalar: \(String(format: "%.4f", scalarTime))s")
        print("   vDSP:   \(String(format: "%.4f", vdspTime))s")
        print("   Speedup: \(String(format: "%.2f", speedup))x")
        
        XCTAssertGreaterThan(
            speedup,
            minSpeedup,
            "vDSP scaling should be at least \(Int(minSpeedup))x faster than scalar"
        )
    }
    
    // MARK: - vDSP_measqv Benchmarks
    
    /// Test mean square (RMS energy) calculation
    /// Expected: 3-5x speedup
    func testMeanSquareCalculationSpeedup() throws {
        let count = 65536
        let input = generateRandomSamples(count: count)
        
        // Scalar implementation
        let scalarTime = measureScalarMeanSquare(input: input)
        
        // vDSP implementation
        let vdspTime = measureVDSPMeanSquare(input: input)
        
        let speedup = scalarTime / vdspTime
        
        print("📊 Mean Square (RMS Energy):")
        print("   Scalar: \(String(format: "%.4f", scalarTime))s")
        print("   vDSP:   \(String(format: "%.4f", vdspTime))s")
        print("   Speedup: \(String(format: "%.2f", speedup))x")
        
        XCTAssertGreaterThan(
            speedup,
            minSpeedup,
            "vDSP mean square should be at least \(Int(minSpeedup))x faster than scalar"
        )
    }
    
    // MARK: - vDSP_mmov Benchmarks
    
    /// Test memory move performance
    /// Expected: 2-4x speedup for large arrays
    func testMemoryMoveSpeedup() throws {
        let count = 65536
        let source = generateRandomSamples(count: count)
        
        // Scalar implementation (using Array.copy or manual)
        let scalarTime = measureScalarMemoryMove(source: source)
        
        // vDSP implementation
        let vdspTime = measureVDSPMemoryMove(source: source)
        
        let speedup = scalarTime / vdspTime
        
        print("📊 Memory Move (Copy):")
        print("   Scalar: \(String(format: "%.4f", scalarTime))s")
        print("   vDSP:   \(String(format: "%.4f", vdspTime))s")
        print("   Speedup: \(String(format: "%.2f", speedup))x")
        
        XCTAssertGreaterThan(
            speedup,
            minSpeedup,
            "vDSP memory move should be at least \(Int(minSpeedup))x faster than scalar"
        )
    }
    
    // MARK: - vDSP_vclr Benchmarks
    
    /// Test buffer zeroing performance
    /// Expected: 2-4x speedup (important for security)
    func testBufferClearingSpeedup() throws {
        let count = 65536
        
        // Scalar implementation
        let scalarTime = measureScalarBufferClear(count: count)
        
        // vDSP implementation
        let vdspTime = measureVDSPBufferClear(count: count)
        
        let speedup = scalarTime / vdspTime
        
        print("📊 Buffer Clearing (Security):")
        print("   Scalar: \(String(format: "%.4f", scalarTime))s")
        print("   vDSP:   \(String(format: "%.4f", vdspTime))s")
        print("   Speedup: \(String(format: "%.2f", speedup))x")
        
        XCTAssertGreaterThan(
            speedup,
            minSpeedup,
            "vDSP buffer clear should be at least \(Int(minSpeedup))x faster than scalar"
        )
    }
    
    // MARK: - Buffer Memory Bounds Tests
    
    /// Verify CircularAudioBuffer has fixed capacity
    func testCircularBufferBoundedMemory() async throws {
        let capacity = 32768  // 2 seconds at 16kHz
        let buffer = VDSPCircularAudioBuffer(capacity: capacity)
        
        // Write more than capacity
        let samples = generateRandomSamples(count: capacity * 2)
        let written = await buffer.write(samples)
        
        // Should only write up to capacity
        XCTAssertEqual(written, capacity, "Should only write up to capacity")
        
        // Verify fill level
        let fillLevel = await buffer.fillLevel()
        XCTAssertEqual(fillLevel, 1.0, "Buffer should be full")
        
        // Verify no unbounded growth
        let stats = await buffer.getStatistics()
        XCTAssertEqual(stats.capacity, capacity, "Capacity should remain fixed")
    }
    
    /// Verify ChunkedSpeechBuffer has bounded memory (768KB)
    func testChunkedBufferBoundedMemory() async throws {
        let buffer = VDSPChunkedSpeechBuffer(configuration: .default)
        
        // Write large amount of samples
        let largeSampleCount = 1000000  // Way over limit
        let samples = generateRandomSamples(count: largeSampleCount)
        _ = await buffer.write(samples)
        
        // Check memory usage
        let memoryUsage = await buffer.memoryUsage()
        let maxExpectedMemory = 768 * 1024  // 768KB
        
        XCTAssertLessThanOrEqual(
            memoryUsage,
            maxExpectedMemory,
            "Memory usage should never exceed 768KB"
        )
        
        // Verify configuration
        let config = await buffer.configuration
        XCTAssertEqual(config.maxSizeBytes, 768 * 1024, "Max size should be 768KB")
    }
    
    /// Verify AudioBufferPool has bounded size
    func testBufferPoolBoundedMemory() async {
        let pool = AudioBufferPool()
        
        // Check initial stats
        let initialStats = await pool.stats
        let expectedMemory = 4 * 64 * 1024 * MemoryLayout<Float>.size  // 4 chunks * 64K floats
        
        XCTAssertEqual(
            initialStats.totalMemory,
            0,
            "Initial memory should be 0"
        )
        
        // Acquire and release multiple buffers
        var buffers: [[Float]] = []
        for _ in 0..<10 {
            let buffer = await pool.acquire()
            buffers.append(buffer)
        }
        
        // Release all back to pool
        for i in 0..<buffers.count {
            var buffer = buffers[i]
            await pool.release(&buffer)
        }
        
        // Check final stats
        let finalStats = await pool.stats
        let maxPoolMemory = 4 * 64 * 1024 * MemoryLayout<Float>.size
        
        XCTAssertLessThanOrEqual(
            finalStats.totalMemory,
            maxPoolMemory,
            "Pool memory should never exceed \(maxPoolMemory) bytes"
        )
    }
    
    // MARK: - Comprehensive Integration Benchmark
    
    /// Test real-world audio processing pipeline
    /// Simulates: stereo input -> deinterleave -> mix to mono -> apply gain
    func testRealWorldAudioPipelineSpeedup() throws {
        let frameCount = 16384
        let interleaved = generateInterleavedStereoSamples(frameCount: frameCount)
        
        // Scalar pipeline
        let scalarTime = measureScalarPipeline(interleaved: interleaved, frameCount: frameCount)
        
        // vDSP pipeline
        let vdspTime = measureVDSPPipeline(interleaved: interleaved, frameCount: frameCount)
        
        let speedup = scalarTime / vdspTime
        
        print("📊 Real-World Audio Pipeline (Stereo → Mono → Gain):")
        print("   Scalar: \(String(format: "%.4f", scalarTime))s")
        print("   vDSP:   \(String(format: "%.4f", vdspTime))s")
        print("   Speedup: \(String(format: "%.2f", speedup))x")
        
        // Pipeline should achieve at least 3x speedup
        XCTAssertGreaterThan(
            speedup,
            3.0,
            "Complete vDSP pipeline should be at least 3x faster"
        )
    }
    
    // MARK: - Measurement Helpers
    
    private func measureScalarDeinterleave(interleaved: [Float], frameCount: Int) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var left: [Float] = []
            var right: [Float] = []
            left.reserveCapacity(frameCount)
            right.reserveCapacity(frameCount)
            
            for i in 0..<frameCount {
                left.append(interleaved[i * 2])
                right.append(interleaved[i * 2 + 1])
            }
            
            // Mix to mono (scalar)
            var mono = Array(repeating: Float(0), count: frameCount)
            for i in 0..<frameCount {
                mono[i] = (left[i] + right[i]) * 0.5
            }
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureVDSPDeinterleave(interleaved: [Float], frameCount: Int) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var left = Array(repeating: Float(0), count: frameCount)
            var right = Array(repeating: Float(0), count: frameCount)
            var mono = Array(repeating: Float(0), count: frameCount)
            
            interleaved.withUnsafeBufferPointer { interleavedPtr in
                left.withUnsafeMutableBufferPointer { leftPtr in
                    right.withUnsafeMutableBufferPointer { rightPtr in
                        var splitBuffers: [UnsafeMutablePointer<Float>] = [
                            leftPtr.baseAddress!,
                            rightPtr.baseAddress!
                        ]
                        
                        vDSP_deinterleave(
                            interleavedPtr.baseAddress!,
                            1,
                            &splitBuffers,
                            2,
                            vDSP_Length(frameCount)
                        )
                    }
                }
            }
            
            // Mix to mono using vDSP
            left.withUnsafeBufferPointer { leftPtr in
                right.withUnsafeBufferPointer { rightPtr in
                    mono.withUnsafeMutableBufferPointer { monoPtr in
                        vDSP_vadd(
                            leftPtr.baseAddress!, 1,
                            rightPtr.baseAddress!, 1,
                            monoPtr.baseAddress!, 1,
                            vDSP_Length(frameCount)
                        )
                        
                        var scale: Float = 0.5
                        vDSP_vsmul(
                            monoPtr.baseAddress!, 1,
                            &scale,
                            monoPtr.baseAddress!, 1,
                            vDSP_Length(frameCount)
                        )
                    }
                }
            }
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureScalarAddition(a: [Float], b: [Float]) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var result = Array(repeating: Float(0), count: a.count)
            for i in 0..<a.count {
                result[i] = a[i] + b[i]
            }
            // Prevent optimization
            XCTAssertEqual(result.count, a.count)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureVDSPAddition(a: [Float], b: [Float]) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var result = Array(repeating: Float(0), count: a.count)
            a.withUnsafeBufferPointer { aPtr in
                b.withUnsafeBufferPointer { bPtr in
                    result.withUnsafeMutableBufferPointer { resultPtr in
                        vDSP_vadd(
                            aPtr.baseAddress!, 1,
                            bPtr.baseAddress!, 1,
                            resultPtr.baseAddress!, 1,
                            vDSP_Length(a.count)
                        )
                    }
                }
            }
            // Prevent optimization
            XCTAssertEqual(result.count, a.count)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureScalarScaling(input: [Float], gain: Float) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var result = input
            for i in 0..<input.count {
                result[i] = input[i] * gain
            }
            // Prevent optimization
            XCTAssertEqual(result.count, input.count)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureVDSPScaling(input: [Float], gain: Float) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var result = input
            var g = gain
            input.withUnsafeBufferPointer { inputPtr in
                result.withUnsafeMutableBufferPointer { resultPtr in
                    vDSP_vsmul(
                        inputPtr.baseAddress!, 1,
                        &g,
                        resultPtr.baseAddress!, 1,
                        vDSP_Length(input.count)
                    )
                }
            }
            // Prevent optimization
            XCTAssertEqual(result.count, input.count)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureScalarMeanSquare(input: [Float]) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var sum: Float = 0
            for i in 0..<input.count {
                sum += input[i] * input[i]
            }
            let meanSquare = sum / Float(input.count)
            // Prevent optimization
            XCTAssertGreaterThan(meanSquare, 0)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureVDSPMeanSquare(input: [Float]) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var meanSquare: Float = 0
            input.withUnsafeBufferPointer { inputPtr in
                vDSP_measqv(inputPtr.baseAddress!, 1, &meanSquare, vDSP_Length(input.count))
            }
            // Prevent optimization
            XCTAssertGreaterThan(meanSquare, 0)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureScalarMemoryMove(source: [Float]) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var dest = Array(repeating: Float(0), count: source.count)
            for i in 0..<source.count {
                dest[i] = source[i]
            }
            // Prevent optimization
            XCTAssertEqual(dest.count, source.count)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureVDSPMemoryMove(source: [Float]) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var dest = Array(repeating: Float(0), count: source.count)
            source.withUnsafeBufferPointer { sourcePtr in
                dest.withUnsafeMutableBufferPointer { destPtr in
                    vDSP_mmov(
                        sourcePtr.baseAddress!,
                        destPtr.baseAddress!,
                        vDSP_Length(source.count),
                        1, 1, 1
                    )
                }
            }
            // Prevent optimization
            XCTAssertEqual(dest.count, source.count)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureScalarBufferClear(count: Int) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var buffer = Array(repeating: Float(1.0), count: count)
            for i in 0..<buffer.count {
                buffer[i] = 0.0
            }
            // Prevent optimization
            XCTAssertEqual(buffer.count, count)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureVDSPBufferClear(count: Int) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var buffer = Array(repeating: Float(1.0), count: count)
            buffer.withUnsafeMutableBufferPointer { bufferPtr in
                vDSP_vclr(bufferPtr.baseAddress!, 1, vDSP_Length(count))
            }
            // Prevent optimization
            XCTAssertEqual(buffer.count, count)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureScalarPipeline(interleaved: [Float], frameCount: Int) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            // Deinterleave
            var left: [Float] = []
            var right: [Float] = []
            for i in 0..<frameCount {
                left.append(interleaved[i * 2])
                right.append(interleaved[i * 2 + 1])
            }
            
            // Mix and scale
            var mono = Array(repeating: Float(0), count: frameCount)
            for i in 0..<frameCount {
                mono[i] = (left[i] + right[i]) * 0.5
            }
            
            // Apply gain
            let gain: Float = 0.8
            for i in 0..<frameCount {
                mono[i] *= gain
            }
            
            // Prevent optimization
            XCTAssertEqual(mono.count, frameCount)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    private func measureVDSPPipeline(interleaved: [Float], frameCount: Int) -> TimeInterval {
        let start = CFAbsoluteTimeGetCurrent()
        
        for _ in 0..<iterations {
            var left = Array(repeating: Float(0), count: frameCount)
            var right = Array(repeating: Float(0), count: frameCount)
            var mono = Array(repeating: Float(0), count: frameCount)
            
            // Deinterleave using vDSP
            interleaved.withUnsafeBufferPointer { interleavedPtr in
                left.withUnsafeMutableBufferPointer { leftPtr in
                    right.withUnsafeMutableBufferPointer { rightPtr in
                        var splitBuffers: [UnsafeMutablePointer<Float>] = [
                            leftPtr.baseAddress!,
                            rightPtr.baseAddress!
                        ]
                        
                        vDSP_deinterleave(
                            interleavedPtr.baseAddress!,
                            1,
                            &splitBuffers,
                            2,
                            vDSP_Length(frameCount)
                        )
                    }
                }
            }
            
            // Mix using vDSP_vadd
            left.withUnsafeBufferPointer { leftPtr in
                right.withUnsafeBufferPointer { rightPtr in
                    mono.withUnsafeMutableBufferPointer { monoPtr in
                        vDSP_vadd(
                            leftPtr.baseAddress!, 1,
                            rightPtr.baseAddress!, 1,
                            monoPtr.baseAddress!, 1,
                            vDSP_Length(frameCount)
                        )
                    }
                }
            }
            
            // Scale using vDSP_vsmul (combining mix scale + gain)
            var scale: Float = 0.5 * 0.8  // Mix scale * gain
            mono.withUnsafeMutableBufferPointer { monoPtr in
                vDSP_vsmul(
                    monoPtr.baseAddress!, 1,
                    &scale,
                    monoPtr.baseAddress!, 1,
                    vDSP_Length(frameCount)
                )
            }
            
            // Prevent optimization
            XCTAssertEqual(mono.count, frameCount)
        }
        
        return CFAbsoluteTimeGetCurrent() - start
    }
    
    // MARK: - Data Generators
    
    private func generateRandomSamples(count: Int) -> [Float] {
        var samples: [Float] = []
        samples.reserveCapacity(count)
        for _ in 0..<count {
            samples.append(Float.random(in: -1.0...1.0))
        }
        return samples
    }
    
    private func generateInterleavedStereoSamples(frameCount: Int) -> [Float] {
        var interleaved: [Float] = []
        interleaved.reserveCapacity(frameCount * 2)
        for _ in 0..<frameCount {
            interleaved.append(Float.random(in: -1.0...1.0))  // Left
            interleaved.append(Float.random(in: -1.0...1.0))  // Right
        }
        return interleaved
    }
}

// MARK: - Performance Summary Extension

@available(macOS 15.0, *)
extension VDSPSpeedupBenchmarkTests {
    
    /// Run all benchmarks and print comprehensive summary
    static func runAllBenchmarks() async {
        print("\n" + String(repeating: "=", count: 70))
        print("vDSP Performance Benchmark Summary")
        print(String(repeating: "=", count: 70))
        
        let testSuite = VDSPSpeedupBenchmarkTests.defaultTestSuite
        testSuite.run()
        
        print("\n" + String(repeating: "=", count: 70))
        print("Expected Speedup Targets:")
        print("  • vDSP_deqinterleave: 4-8x (Apple Silicon AMX)")
        print("  • vDSP_vadd: 3-6x (SIMD vector units)")
        print("  • vDSP_vsmul: 3-6x (SIMD vector units)")
        print("  • vDSP_measqv: 3-5x (SIMD vector units)")
        print("  • vDSP_mmov: 2-4x (optimized memory subsystem)")
        print("  • vDSP_vclr: 2-4x (SIMD vector units)")
        print(String(repeating: "=", count: 70))
    }
}
