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
        var continuations: [CheckedContinuation<Element?, Never>] = []

        func next() async -> Element? {
            return await withCheckedContinuation({ continuation in
                continuations.append(continuation)
            })
        }

        func send(_ element: Element) {
            let continuation = continuations.removeFirst()
            continuation.resume(returning: element)
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

    try await Task.sleep(nanoseconds: 1)
    await asyncStream.send(Int.random(in: 0...99))

    try await Task.sleep(nanoseconds: 1)
    await asyncStream.send(Int.random(in: 0...99))

    try await Task.sleep(nanoseconds: 1)
    await asyncStream.send(Int.random(in: 0...99))
}

//Task.detached {
//    try await Task.sleep(nanoseconds: 1000)
//    notificationCenter.send(Int.random(in: 0...99))
//}
//
