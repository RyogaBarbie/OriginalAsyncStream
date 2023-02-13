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

enum OriginalError: Error {
    case somethingHappend
}

let asyncStream =  SimpleAsyncThrowingStream<Int>() { terminal in
    switch terminal {
    case .finished: print("終了しました")
    case .failed(let error):
        print("\(error)によって失敗しました")
    }
}

Task.detached {
    do {
        for try await element in asyncStream {
            print(element)
        }
    } catch {
        print("\(error)が発生したのでループを終了します")
    }
}

//Task.detached {
//    for await notify in notificationCenter {
//        print("2つ目")
//        print(notify * 10)
//    }
//}


Task.detached {
    await asyncStream.send(Int.random(in: 0...99))
    await asyncStream.send(Int.random(in: 0...99))
    await asyncStream.send(Int.random(in: 0...99))

    try await Task.sleep(nanoseconds: 1_000_000_000)
    await asyncStream.send(Int.random(in: 0...99))
    await asyncStream.send(Int.random(in: 0...99))
}

Task.detached {
    try await Task.sleep(nanoseconds: 800_000_000)
    asyncStream.finish(OriginalError.somethingHappend)
}

