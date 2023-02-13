@available(iOS 16, *)
public struct  SimpleAsyncThrowingStream<Element>: AsyncSequence {
    public typealias Element = Element
    public typealias AsyncIterator = Iterator
    public typealias TerminationHandler = @Sendable (Terminal) -> Void

    private let _storage: Storage

    public init(_ terminationHandler: @escaping TerminationHandler) {
        self._storage = Storage(terminationHandler)
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(_storage)
    }

    public func send(_ element: Element) async {
        await _storage.send(element)
    }

    public func finish(_ error: Error? = nil) {
        Task.detached {
            await _storage.finish(error)
        }
    }
}

extension  SimpleAsyncThrowingStream {
    public struct Iterator: AsyncIteratorProtocol {
        private let _storage: Storage

        init(_ storage: Storage) {
            self._storage = storage
        }

        public func next() async throws -> Element? {
            try await _storage.next()
        }
    }
}

extension  SimpleAsyncThrowingStream {
    public enum Terminal {
        case finished
        case failed(Error)
    }

    actor Storage {
        private struct State {
            var continuation: CheckedContinuation<Element?, Error>? = nil
            var pending = [Element]()
            var terminationHandler: TerminationHandler?
            var terminal: Terminal? = nil
        }

        private var state: State

        init(_ terminationHandler: @escaping TerminationHandler) {
            self.state = State(terminationHandler: terminationHandler)
        }

        func next() async throws -> Element? {
            // finishより前にsendされた値が正しく送信されるか
            // finishが呼ばれたタイミングで実行されるかを確認する用
            // try await Task.sleep(nanoseconds: 1_000_000_000)
            return try await withCheckedThrowingContinuation({ _continuation in
                if state.pending.count > 0 {
                    let sendValue = state.pending.removeFirst()
                    _continuation.resume(returning: sendValue)
                } else if let termianl = state.terminal {
                    state.continuation = nil

                    switch termianl {
                    case .finished:
                        _continuation.resume(returning: nil)
                    case .failed(let error):
                        _continuation.resume(throwing: error)
                    }
                } else {
                    state.continuation = _continuation
                }
            })
        }

        func send(_ element: Element) {
            if let continuation = state.continuation {
                state.continuation = nil
                continuation.resume(returning: element)
            } else if state.terminal == nil {
                state.pending.append(element)
            }
        }

        func finish(_ error: Error?) {
            guard state.terminal == nil else { return }

            let handler = state.terminationHandler

            let terminal: Terminal
            if let _error = error {
                terminal = .failed(_error)
            } else {
                terminal = .finished
            }

            state.terminal = terminal
            state.terminationHandler = nil

            if let continuation = state.continuation {
                state.continuation = nil
                switch terminal {
                case .finished:
                    continuation.resume(returning: nil)
                case .failed(let error):
                    continuation.resume(throwing: error)
                }
            }

            handler?(terminal)
        }
    }
}

@available(iOS 16, *)
public class  SimpleAsyncThrowingMultiStream<Element>: AsyncSequence, @unchecked Sendable  {
    public typealias Element = Element
    public typealias AsyncIterator = Iterator
    public typealias TerminationHandler = @Sendable (Terminal) -> Void

    private var _storages: [Storage] = []
    private var terminationHandler: TerminationHandler?

    public init(_ terminationHandler: @escaping TerminationHandler) {
        self.terminationHandler = terminationHandler
    }

    public func makeAsyncIterator() -> Iterator {
        let storage = Storage()
        _storages.append(storage)
        return Iterator(storage)
    }

    /// 複数のTaskで同時にsendを叩いだ場合、購読側で実際にsendを叩いた順番とは違う順番でElementが流れてくる可能性がある。
    public func send(_ element: Element) async {
        await withTaskGroup(of: Void.self) { group in
            for _storage in _storages {
                group.addTask {
                    await _storage.send(element)
                }
            }
        }
    }

    public func finish(_ error: Error? = nil) {
        let handler = terminationHandler
        terminationHandler = nil

        let terminal: Terminal
        if let _error = error {
            terminal = .failed(_error)
        } else {
            terminal = .finished
        }

        handler?(terminal)

        Task.detached {
            await withTaskGroup(of: Void.self, body: { group in
                for _storage in self._storages {
                    group.addTask {
                        await _storage.finish(terminal)
                    }
                }
            })
        }
    }
}

extension  SimpleAsyncThrowingMultiStream {
    public struct Iterator: AsyncIteratorProtocol {
        private let _storage: Storage

        init(_ storage: Storage) {
            self._storage = storage
        }

        public func next() async throws -> Element? {
            try await _storage.next()
        }
    }
}

extension  SimpleAsyncThrowingMultiStream {
    public enum Terminal {
        case finished
        case failed(Error)
    }

    actor Storage {
        private struct State {
            var continuation: CheckedContinuation<Element?, Error>? = nil
            var pending = [Element]()
            var terminal: Terminal? = nil
        }

        private var state: State = .init()

        init() {}

        func next() async throws -> Element? {
            // finishより前にsendされた値が正しく送信されるか
            // finishが呼ばれたタイミングで実行されるかを確認する用
//             try await Task.sleep(nanoseconds: 1_000_000_000)
            return try await withCheckedThrowingContinuation({ _continuation in
                if state.pending.count > 0 {
                    let sendValue = state.pending.removeFirst()
                    _continuation.resume(returning: sendValue)
                } else if let termianl = state.terminal {
                    state.continuation = nil

                    switch termianl {
                    case .finished:
                        _continuation.resume(returning: nil)
                    case .failed(let error):
                        _continuation.resume(throwing: error)
                    }
                } else {
                    state.continuation = _continuation
                }
            })
        }

        func send(_ element: Element) {
            if let continuation = state.continuation {
                state.continuation = nil
                continuation.resume(returning: element)
            } else if state.terminal == nil {
                state.pending.append(element)
            }
        }

        func finish(_ terminal: Terminal) {
            state.terminal = terminal

            if let continuation = state.continuation {
                state.continuation = nil
                switch terminal {
                case .finished:
                    continuation.resume(returning: nil)
                case .failed(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}


enum OriginalError: Error {
    case somethingHappend
}

//let asyncStream =  SimpleAsyncThrowingStream<Int>() { terminal in
let asyncStream =  SimpleAsyncThrowingMultiStream<Int>() { terminal in
    switch terminal {
    case .finished: print("終了が呼ばれました")
    case .failed(let error):
        print("failed \(error)が呼ばれました")
    }
}

Task.detached {
    do {
        for try await element in asyncStream {
            print("1つ目 \(element)")
        }
    } catch {
        print("1つ目に\(error)が発生したのでループを終了します")
    }
}
Task.detached {
    do {
        for try await element in asyncStream {
            print("2つ目 \(element)")
        }
    } catch {
        print("2つ目に\(error)が発生したのでループを終了します")
    }
}
Task.detached {
    do {
        for try await element in asyncStream {
            print("3つ目 \(element)")
        }
    } catch {
        print("3つ目に\(error)が発生したのでループを終了します")
    }
}


Task.detached {
    await asyncStream.send(Int.random(in: 0...99))
    await asyncStream.send(Int.random(in: 0...99))

    try await Task.sleep(nanoseconds: 1_000_000_000)
    await asyncStream.send(Int.random(in: 0...99))
}
Task.detached {
    await asyncStream.send(Int.random(in: 0...99))

    try await Task.sleep(nanoseconds: 1_000_000_000)
    await asyncStream.send(Int.random(in: 0...99))
}

Task.detached {
    try await Task.sleep(nanoseconds: 800_000_000)
    asyncStream.finish(OriginalError.somethingHappend)
}

