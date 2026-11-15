# async.nu — the applicative functor over nushell background jobs.
#
# The kap magic translated. In kap, `.with(Kap { fetchA() })` applies a
# DEFERRED computation to a curried function; the graph runs deferred values
# concurrently and fills the structure as they land.
#
# Nushell's deferred value is the background job (a thread, 0.117): spawn it;
# it sends its result to the main mailbox (`job send 0`) carrying its
# position; the main thread blocks in `job recv` (zero polling) and structure
# order is restored by sorting on the index. `--timeout` is the failure
# signal: on expiry every spawned job is killed and the error is honest.
# Calls are isolated by a per-call random tag: a killed job's dying catch
# can still deliver its outcome (kill races the send), and the tag keeps
# that stale message away from every later call (see traverse-jobs).
#
# Verified live on 0.117.0: closure capture into spawned jobs, mailbox FIFO,
# out-of-order arrival restored by index, staggered completion, timeout+kill.
# Jobs are threads — they die with the nu process. In-process async only;
# anything that must survive goes to a LaunchAgent, never here.

use currying.nu apply-args

# Applicative traverse over jobs: run every closure in its own thread,
# concurrently, and collect the results as a list IN STRUCTURE ORDER
# (arrival order is racy; the index restores it).
export def traverse-jobs [
    --timeout: duration = 5min
]: list<closure> -> list<any> {
    let fs: list<closure> = $in
    let n: int = ($fs | length)
    if $n == 0 { return [] }
    # MAILBOX ISOLATION LAW: the process mailbox is shared, and job kill
    # races the job's dying catch — an interrupted job can still package the
    # interrupt as an error and `job send` it before the thread dies
    # (measured live: a stale "0: Operation interrupted" poisoned the NEXT
    # call). One random tag per CALL: every job of this call sends with it,
    # the collector filters by it, foreign messages are never consumed.
    # Element order rides the body's i field.
    let callTag: int = (random int 1..1000000000)
    let ids: list<int> = ($fs | enumerate | each {|row|
        job spawn --description "nushell-fp traverse" {
            # A crashed element must STILL report — otherwise the collector
            # blocks on its missing message until --timeout. Learned live:
            # 355 agent metadata files, one missing field, a silent hang.
            # The error rides the same mailbox and rethrows after collection,
            # by element index.
            let outcome: any = (try {
                {i: $row.index, v: (do $row.item)}
            } catch {|e|
                {i: $row.index, v: null, error: ($e.msg)}
            })
            $outcome | job send 0 --tag $callTag
        }
    })
    let msgs: list<any> = (1..$n | each {|_|
        try {
            job recv --tag $callTag --timeout $timeout
        } catch {
            # killing an already-exited job errors — never let that replace
            # the honest timeout error
            $ids | each {|id| try { job kill $id } } | ignore
            error make {msg: "nushell-fp traverse-jobs: timeout — a job never finished"}
        }
    })
    let sorted: list<any> = ($msgs | sort-by i)
    # EVERY crashed element is named, in structure order — dropping later
    # ones hides how many things actually failed (accumulation law).
    let crashed: list<any> = ($sorted | where {|m| $m.error? != null})
    if not ($crashed | is-empty) {
        let detail: string = ($crashed | each {|m| $"($m.i): ($m.error)"} | str join "; ")
        error make {msg: $"nushell-fp traverse-jobs: failed elements — ($detail)"}
    }
    $sorted | get v
}

# Concurrent record filling: every field closure runs as a job; the record
# exists when the last field lands. This is the structure-filled applicative
# — build-record's concurrent sibling.
export def build-record-jobs [
    --timeout: duration = 5min
]: record -> record {
    let spec: record = $in
    if ($spec | columns | is-empty) { return {} }
    let ks: list<string> = ($spec | columns)
    # traverse-jobs errors name element indexes (= field order here); prefix
    # the record context so the failure reads in the caller's terms
    let vs: list<any> = (try {
        $spec | values | traverse-jobs --timeout $timeout
    } catch {|e|
        error make {msg: $"nushell-fp build-record-jobs: ($e.msg)"}
    })
    $ks | zip $vs | each {|pair| {key: $pair.0, value: $pair.1}} | transpose -r -d
}

# The kap `.with` chain in ONE call: run the arg-producing closures
# concurrently, then feed the collected list into a curried closure.
# [{|| fetchA}, {|| fetchB}] | apply-async (curry2 mk)
export def apply-async [
    c: closure
    --timeout: duration = 5min
]: list<closure> -> any {
    $in | traverse-jobs --timeout $timeout | apply-args $c
}
