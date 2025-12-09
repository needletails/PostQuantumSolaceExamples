//
//  IRCEventLoopExecutor.swift
//  PostQuantumSolaceDemo
//
//  Created by Cole M on 9/12/25.
//
import NIOCore
import NeedleTailAsyncSequence

/**
 _IRCEventLoopExecutor_ A custom executor used in order to run code Swift Concurrent code on the NIO event loop.
 **/

public final class IRCEventLoopExecutor: AnyExecutor {
    
    let eventLoop: EventLoop
    let shouldExecuteAsTask: Bool
    
    init(eventLoop: EventLoop, shouldExecuteAsTask: Bool = true) {
        self.eventLoop = eventLoop
        self.shouldExecuteAsTask = shouldExecuteAsTask
    }
    
    public func asUnownedTaskExecutor() -> UnownedTaskExecutor {
        UnownedTaskExecutor(ordinary: self)
    }
    
    public func checkIsolated() {
        precondition(eventLoop.inEventLoop, "The callee is not isolated to this EventLoop")
    }
    
    public func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        eventLoop.execute { [weak self] in
            guard let self else { return }
            if self.shouldExecuteAsTask {
                job.runSynchronously(on: self.asUnownedTaskExecutor())
            } else {
                job.runSynchronously(on: self.asUnownedSerialExecutor())
            }
        }
    }
    
    public func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(complexEquality: self)
    }
}
