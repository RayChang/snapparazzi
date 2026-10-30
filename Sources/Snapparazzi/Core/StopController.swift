import Foundation
import Dispatch

final class StopController: @unchecked Sendable {
    private let lock = NSLock()
    private let wakeSemaphore = DispatchSemaphore(value: 0)
    private var stopRequested = false
    private var activeProcess: Process?

    var shouldStop: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopRequested
    }

    @discardableResult
    func requestStop() -> Bool {
        lock.lock()
        let isFirstRequest = !stopRequested
        stopRequested = true
        let process = activeProcess
        lock.unlock()

        process?.interrupt()
        wakeSemaphore.signal()
        return isFirstRequest
    }

    func register(_ process: Process) {
        lock.lock()
        activeProcess = process
        let shouldInterrupt = stopRequested
        lock.unlock()

        if shouldInterrupt {
            process.interrupt()
        }
    }

    func unregister(_ process: Process) {
        lock.lock()
        if activeProcess === process {
            activeProcess = nil
        }
        lock.unlock()
    }

    func wait(until deadline: DispatchTime) {
        guard !shouldStop else { return }
        _ = wakeSemaphore.wait(timeout: deadline)
    }
}
