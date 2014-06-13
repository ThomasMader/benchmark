#!/bin/sh

echo 'run fastaredux in D:'
time ./fastaredux 250000

echo 'run fastaredux in Java:'
time java -server -XX:+TieredCompilation -XX:+AggressiveOpts fastaredux 250000
