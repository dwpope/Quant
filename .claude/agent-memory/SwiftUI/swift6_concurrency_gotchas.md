# Swift 6.3 strict-concurrency gotchas (general, cross-project)

Found while implementing an actor that composes several non-Sendable "kit"
classes in `~/Developer/Remember the moment` (AppCore's `CaptureCoordinator`,
2026-07). Verified with isolated `swiftc`/SwiftPM repros before touching real
code — not guesses. Toolchain: Apple Swift 6.3.2 (swiftlang-6.3.2.1.108),
tools-version 6.2 packages (Swift 6 language mode, complete concurrency
checking).

## 1. Calling an async method on a non-Sendable class stored as an actor property
If an actor stores `let helper: SomeNonSendableClass` and calls
`await helper.doThing()` where `doThing()` is `async` but `SomeNonSendableClass`
has no actor isolation of its own, you get:
`error: sending 'self.helper' risks causing data races` /
`sending 'self'-isolated 'self.helper' to nonisolated instance method ... risks
causing data races between nonisolated and 'self'-isolated uses`.
This fires ONLY for `async` calls — plain synchronous method calls on the same
non-Sendable property never trigger it (no suspension point, no reentrancy
risk as far as the compiler's region checker is concerned).
- Fix (when you can't make the helper Sendable, e.g. it's a dependency's type
  you're not allowed to touch): mark the property
  `private nonisolated(unsafe) let helper: SomeNonSendableClass` — valid and
  idiomatic IF you can show the actor's own control flow (e.g. a state-machine
  guard) already serializes access so only one call is ever in flight. Document
  *why* it's safe in a comment; this is a case where you're overriding the
  type system with a proven invariant, not just suppressing a warning.

## 2. Actor `let` stored properties and cross-module access
An actor's immutable, `Sendable`-typed stored property (e.g.
`public let events: AsyncStream<Foo>`) can be read from outside the actor
**without `await`** when the caller is in the SAME module as the actor. From a
DIFFERENT module (e.g. a test target with `@testable import` or a normal
`import` of the library), the exact same access gives:
`error: actor-isolated property 'X' cannot be accessed from outside of the actor`.
This is Swift's conservative library-evolution stance: across a module
boundary it can't assume the stored `let` won't become a computed property
later, so it isolates it by default. Confirmed via a minimal two-target SwiftPM
package reproduction (single-module version compiles clean; two-module version
errors on the exact same code).
- Fix A (preferred when the property is genuinely meant for free external
  observation, e.g. a UI-facing state stream): mark it
  `public nonisolated let events: AsyncStream<Foo>` in the actor. No caller
  changes needed anywhere.
- Fix B (if you can't touch the actor): add an explicit `await` at the access
  site: `for await x in await someActor.events { ... }` — valid syntax, the
  `await` on the property access is separate from the `for await` sequence
  iteration keyword.

## 3. Fixed epoch-offset `Date` constants in test fixtures go stale
A pattern like `let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)`
used to mean "a recent instant" at authoring time will silently break any test
logic that filters on `now() - someWindow <= t0` once enough real wall-clock
time has passed (weeks/months), because the code under test's default clock
is real `Date()`, decoupled from the fixture's frozen instant. Symptom: tests
pass right after being written, then fail mysteriously months later with no
code change — often masked because a "should be empty" assertion passes
vacuously even when the intended code path never ran.
- Prefer `let t0 = Date()` (computed fresh per test run) over a hardcoded
  epoch offset, UNLESS the system under test's clock is *also* injected and
  pinned to the same fixed instant (check for a `now:`/clock-injection
  parameter before assuming a fixed Date is safe).

## 4. Capturing a non-Sendable class in a `@Sendable` closure
Passing a plain (non-`Sendable`) reference type into a parameter typed
`@escaping @Sendable (Args) -> Void` — e.g. wiring a class's own
`onInterruption`/callback property through to a dependency that requires
`@Sendable` — fails to compile if the closure captures `self` or another
non-`Sendable` class instance:
`error: capture of 'x' with non-Sendable type 'SomeClass' in a '@Sendable'
closure`. This is a different trigger from gotcha #1 (that's about `async`
calls on a stored property; this is about closure capture, no `async` needed).
- Fix: if the captured class's stored state is immutable after `init` (all
  `let`, no mutation of `self` in its methods), mark it
  `final class SomeClass: @unchecked Sendable` at the declaration — same
  justification pattern as other reference-safe kit types in a codebase (locks,
  or here, plain immutability). Confirmed safe in `~/Developer/Remember the
  moment`'s `CaptureKit/Sources/CaptureKit/ProbeLog.swift` (stored `fileURL`/
  `encoder`/`decoder` are all `let`; `record()` never mutates `self`) when a
  `GlassesVisualSource.init(onInterruption: @escaping @Sendable (String) ->
  Void)` closure needed to capture a `ProbeLog` to forward interruption
  reasons into it (2026-07 review fix wave, Task 12).
- Related init-order rule: a stored property whose initializer must capture a
  *sibling* stored property in a closure (e.g. `let dependency:
  SomeClass` built as `SomeClass(onEvent: { [probe] in probe.record(...) })`)
  cannot use an inline default-value expression (`let dependency =
  SomeClass(...)` at the property declaration site) — that runs before `self`
  exists. Give the property a type-only declaration (`let dependency:
  SomeClass`) and assign it inside `init()`'s body, strictly after the sibling
  property (`self.probe = probe`) has already been assigned.

## 5. Actor reentrancy at `await kit.start()`/`await kit.stop()` — FIFO `Task` chain fix
An actor method (`arm()`) that does `guard idempotencyCheck() else { return }; try await
source.start()` is NOT safe from a second actor method (`disarm()`) interleaving at its
own `await source.stop()` — actor reentrancy means the actor is free to process a new
external call the instant the first method suspends at ANY `await`, including one deep
inside a kit's start/stop. If the kit type's `@unchecked Sendable` justification claims
"the actor serializes start/stop," that claim is FALSE unless something explicitly
prevents this interleaving — a synchronous guard flag is not enough, because the race
window is exactly the suspension the guard can't see across.
- Fix: give the actor a `private var transition: Task<Void, Never>?` chain. Each public
  entry point (`arm()`/`disarm()`) captures `let prior = transition`, builds `let task =
  Task { [weak self] in await prior?.value; await self?.performX() }`, assigns
  `transition = task`, then `await task.value`. This works because reading/writing
  `transition` itself is synchronous (no `await` in between) — safe under actor
  isolation — and every subsequent transition's `Task` blocks on the previous one's
  `.value` before touching the kit, so `start()`/`stop()` can never overlap regardless
  of how many callers race the public entry points concurrently. Move the ORIGINAL
  method body into a `private func performX()` that never itself awaits `transition`
  (awaiting it there would deadlock: the current transition is already what's blocking
  on it).
- Throws preservation: if the original method threw (`arm() async throws`) and you want
  a caller who legitimately checks the error (not just `try?`) to still see it, box the
  thrown error: `final class ErrorBox: @unchecked Sendable { var error: (any Error)? }`,
  set `box.error = error` inside a `catch` in the chained `Task`, then after `await
  task.value` in the public method, `if let error = box.error { throw error }`. No lock
  needed — the box is written exactly once inside the `Task`, strictly before that
  `Task` completes, and read only after the caller's `await task.value`, which is the
  happens-before edge. Confirmed compiling clean under Swift 6.3 strict concurrency
  (capturing the `@unchecked Sendable` box in the `Task`'s implicit `@Sendable` closure
  raises no diagnostic).
- Test proof pattern: a gated fake conforming to the kit's protocol whose `start()`
  increments an `inFlight` counter, awaits a `withCheckedContinuation` gate, then
  decrements; whose `stop()` sets an `overlapped` flag if `inFlight > 0`. Fire `arm()`
  and `disarm()` as two concurrent unstructured `Task`s, sleep to let scheduling settle,
  assert `overlapped == false` BOTH before releasing the gate and after both tasks
  complete — this deterministically catches the race (no flakiness) because without the
  chain, `disarm()`'s `stop()` really does run while `inFlight` is still 1.
  Verified end-to-end in `~/Developer/Remember the moment`'s `CaptureCoordinator`
  (2026-07-18, call-recovery plan final-review fix wave) — see
  `CaptureCoordinatorTests.disarmDuringInFlightArmNeverOverlapsSourceCalls`.

## 6. `NotificationCenter.default.notifications(named:)` from a `@MainActor` class — no workaround needed
Pattern: a `@MainActor final class` spawns `Task { [weak self] in for await
note in NotificationCenter.default.notifications(named: someName) { ... } }`
from a method called during `init()`, and inside the loop does `guard let self
... await self.someMainActorMethod()`. Expected this async-sequence form to
need `nonisolated`/`Sendable` care or a fallback to the old
`addObserver(forName:object:queue: .main)` API under Swift 6 strict
concurrency — it did NOT. Compiled clean, zero warnings, confirmed via
`xcodebuild -quiet` (exit 0, no diagnostics) in `~/Developer/Remember the
moment`'s `App/AppEnvironment.swift` (AVAudioSession.interruptionNotification
observer, 2026-07 call-recovery plan Task 3). Why it's fine: the unstructured
`Task { ... }` closure does NOT inherit `@MainActor` isolation from its
call site (unlike a method body) — it runs on the cooperative pool, which is
the correct place to await a plain `Sendable` `AsyncSequence`. Every hop back
onto actor-isolated state is an explicit `await` (`await
self.coordinator.disarm()`, `await self.start()`), which is where the
compiler-inserted actor hop happens. `guard let self` upgrades the weak
capture to strong for that iteration only. Conclusion: try the
`notifications(named:)` async-sequence form FIRST on a fresh Swift 6.3-class
toolchain before assuming the addObserver fallback is required — the fallback
appears to be legacy caution, not a current necessity (Apple Swift 6.3.2,
tools-version 6.2, complete concurrency checking).
