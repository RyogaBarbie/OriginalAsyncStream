@available(iOS 16, *)
public struct OriginalAsyncStream<Element>: AsyncSequence {
    public typealias Element = Element

    private let _storage: Storage = Storage()

    public init() {}

    public func send(_ element: Element) async {
        await _storage.send(element)
    }

    public func finish() {

    }
}

extension OriginalAsyncStream {
    public typealias AsyncIterator = Iterator

    public func makeAsyncIterator() -> Iterator {
        Iterator(_storage)
    }

    public struct Iterator: AsyncIteratorProtocol {
        private let _storage: Storage

        init(_ storage: Storage) {
            self._storage = storage
        }

        public func next() async -> Element? {
            await _storage.next()
        }
    }
}

extension OriginalAsyncStream {
    actor Storage {
        private struct State {
            var continuation: CheckedContinuation<Element?, Never>? = nil
            var pending = [Element]()
        }

        private var state = State()

        func next() async -> Element? {
            return await withCheckedContinuation({ _continuation in
                if state.pending.count > 0 {
                    let sendValue = state.pending.removeFirst()
                    _continuation.resume(returning: sendValue)
                } else {
                    state.continuation = _continuation
                }
            })
        }

        func send(_ element: Element) {
            if let continuation = state.continuation {
                state.continuation = nil
                continuation.resume(returning: element)
            } else {
                state.pending.append(element)
            }
        }

        func finish() {

        }
    }
}

let asyncStream = OriginalAsyncStream<Int>()

Task.detached {
    for await element in asyncStream {
        print(element)
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
    await asyncStream.send(Int.random(in: 0...99))
}
