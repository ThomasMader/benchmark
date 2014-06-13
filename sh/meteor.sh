#!/bin/sh

echo 'run meteor in D:'
time ./meteor 2098

echo 'run meteor in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts meteor 2098
