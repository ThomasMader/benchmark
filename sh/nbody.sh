#!/bin/sh

echo 'run nbody in D:'
time ./nbody 50000000

echo 'run nbody in Java:'
cd nbody.tmp
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts nbody 50000000
