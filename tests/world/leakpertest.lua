-- test_orders.py --per-test loads this before the first leak mark: the leak watch then
-- checks each test as it ends (leakwatch.lua).

LeakWatch.perTest = true
