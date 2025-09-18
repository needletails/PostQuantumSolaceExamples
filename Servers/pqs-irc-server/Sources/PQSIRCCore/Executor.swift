//
//  Executor.swift (Library target)
//

import NeedleTailAsyncSequence
import protocol NIOCore.EventLoop
import NIOConcurrencyHelpers

public final class NTSEventLoopExecutor: AnyExecutor, @unchecked Sendable {
  private let lock = NIOLock()
  private let parentLoop: EventLoop
  private var childLoop: EventLoop?
  private let shouldExecuteAsTask: Bool

  public init(eventLoop: EventLoop, shouldExecuteAsTask: Bool = true) {
    self.parentLoop = eventLoop
    self.shouldExecuteAsTask = shouldExecuteAsTask
  }

  public func setChildLoop(_ loop: EventLoop) {
    self.lock.withLockVoid { self.childLoop = loop }
  }

  public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
    UnownedTaskExecutor(ordinary: self)
  }

  public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
    UnownedSerialExecutor(complexEquality: self)
  }

  public func enqueue(_ job: consuming ExecutorJob) {
    let unowned = UnownedJob(job)
    let targetLoop = self.lock.withLock { self.childLoop ?? self.parentLoop }

    targetLoop.execute { [weak self] in
      guard let self = self else { return }
      if self.shouldExecuteAsTask {
        unowned.runSynchronously(on: self.asUnownedTaskExecutor())
      } else {
        unowned.runSynchronously(on: self.asUnownedSerialExecutor())
      }
    }
  }
}


