#!/bin/sh

arg='12'

echo 'run fannkuchredux in D:'
time ./fannkuchredux $arg

echo 'run fannkuchredux in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts fannkuchredux $arg
