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
    let ids: list<int> = ($fs | enumerate | each {|row|
        job spawn --description "nushell-fp traverse" {
            {i: $row.index, v: (do $row.item)} | job send 0 --tag ($row.index + 1)
        }
    })
    let msgs: list<any> = (1..$n | each {|_|
        try {
            job recv --timeout $timeout
        } catch {
            $ids | each {|id| job kill $id} | ignore
            error make {msg: "nushell-fp traverse-jobs: timeout — a job never finished"}
        }
    })
    $msgs | sort-by i | get v
}

# Concurrent record filling: every field closure runs as a job; the record
# exists when the last field lands. This is the structure-filled applicative
# — build-record's concurrent sibling.
export def build-record-jobs [
    --timeout: duration = 5min
]: record -> record {
    let spec: record = $in
    let ks: list<string> = ($spec | columns)
    let vs: list<any> = ($spec | values | traverse-jobs --timeout $timeout)
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
