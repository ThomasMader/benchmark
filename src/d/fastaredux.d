/*
 * The Computer Language Benchmarks Game
 * http://shootout.alioth.debian.org/
 *
 * modified by Enotus
 *
 */

import std.stdio;
import std.stream;
import std.math;
import std.conv;

public class fastaredux {

    static const int LINE_LENGTH = 60;
    static const int OUT_BUFFER_SIZE = 256*1024;
    static const int LOOKUP_SIZE = 4*1024;
    static const double LOOKUP_SCALE = LOOKUP_SIZE - 1;

    static final class Freq {
        char c;
        double p;
        this(char cc, double pp) {c = cc;p = pp;}
    }

    static const string ALU =
            "GGCCGGGCGCGGTGGCTCACGCCTGTAATCCCAGCACTTTGG"
            ~ "GAGGCCGAGGCGGGCGGATCACCTGAGGTCAGGAGTTCGAGA"
            ~ "CCAGCCTGGCCAACATGGTGAAACCCCGTCTCTACTAAAAAT"
            ~ "ACAAAAATTAGCCGGGCGTGGTGGCGCGCGCCTGTAATCCCA"
            ~ "GCTACTCGGGAGGCTGAGGCAGGAGAATCGCTTGAACCCGGG"
            ~ "AGGCGGAGGTTGCAGTGAGCCGAGATCGCGCCACTGCACTCC"
            ~ "AGCCTGGGCGACAGAGCGAGACTCCGTCTCAAAAA";
    
    static Freq[] IUB;
    static Freq[] HomoSapiens;

    static this() {
        IUB = [new Freq('a', 0.27),
        new Freq('c', 0.12),
        new Freq('g', 0.12),
        new Freq('t', 0.27),
        new Freq('B', 0.02),
        new Freq('D', 0.02),
        new Freq('H', 0.02),
        new Freq('K', 0.02),
        new Freq('M', 0.02),
        new Freq('N', 0.02),
        new Freq('R', 0.02),
        new Freq('S', 0.02),
        new Freq('V', 0.02),
        new Freq('W', 0.02),
        new Freq('Y', 0.02)];

	HomoSapiens = [
        new Freq('a', 0.3029549426680),
        new Freq('c', 0.1979883004921),
        new Freq('g', 0.1975473066391),
        new Freq('t', 0.3015094502008)];
    }

    static void sumAndScale(Freq[] a) {
        double p = 0;
        for (int i = 0; i < a.length; i++)
            a[i].p = (p += a[i].p) * LOOKUP_SCALE;
        a[a.length - 1].p = LOOKUP_SCALE;
    }

    static final class Random {
    
        static const int IM = 139968;
        static const int IA = 3877;
        static const int IC = 29573;
        static const double SCALE = LOOKUP_SCALE / IM;
        static int last = 42;

        static double next() {
            return SCALE * (last = (last * IA + IC) % IM);
        }
    }

    static final class Out {
    
        static char buf[];
        static const int lim = OUT_BUFFER_SIZE - 2*LINE_LENGTH - 1;
        static int ct = 0;

	static this() {
	    buf = new char[fastaredux.OUT_BUFFER_SIZE];
	}

        static void checkFlush() {
            if (ct >= lim) { write(buf[0..ct]); ct = 0;}
        }

	static void close() {
	    write(buf[0..ct]); ct = 0;
	}
    }
    
    static final class RandomFasta {

        static Freq[] lookup;

	static this() {
	    lookup=new Freq[fastaredux.LOOKUP_SIZE];
	}
        
        static void makeLookup(Freq[] a) {
            for (int i = 0, j = 0; i < LOOKUP_SIZE; i++) {
                while (a[j].p < i) j++;
                lookup[i] = a[j];
            }
        }

        static void addLine(int bytes) {
            Out.checkFlush();
            int lct=Out.ct;
            while(lct<Out.ct+bytes){
                double r = Random.next();
                int ai = cast(int) r; while (lookup[ai].p < r) ai++;
                Out.buf[lct++] = lookup[ai].c;
            }
            Out.buf[lct++] = cast(byte)'\n';
            Out.ct=lct;
        }

        static void make(string desc, Freq[] a, int n) {
            makeLookup(a);

	    Out.buf[Out.ct..(Out.ct + desc.length)] = desc[0..$];
            Out.ct+=desc.length;
            
            while (n > 0) {
                int bytes = cast(int)fmin(LINE_LENGTH, n);
                addLine(bytes);
                n -= bytes;
            }
        }
    }

    static final class RepeatFasta {

        static void make(string desc, string alu, int n) {
	    Out.buf[Out.ct..(Out.ct + desc.length)] = desc[0..$];
            Out.ct+=desc.length;

            char buf[] = new char[alu.length + LINE_LENGTH];
            for (int i = 0; i < buf.length; i += alu.length) {
		int min = cast(int)fmin(alu.length, buf.length - i);
		buf[i..(i + min)] = alu[0..min];
	    }

            int pos = 0;
            while (n > 0) {
                int bytes = cast(int)fmin(LINE_LENGTH, n);
                Out.checkFlush();
		Out.buf[Out.ct..(Out.ct + bytes)] = buf[pos..(pos + bytes)];Out.ct+=bytes;
                Out.buf[Out.ct++] = cast(byte)'\n';
                pos = cast(int)((pos + bytes) % alu.length);
                n -= bytes;
            }
        }
    }
}

void main(string[] args) {
    int n = 2500000;
    if (args.length > 1) 
	n = to!int(args[1]);

    fastaredux.sumAndScale(fastaredux.IUB);
    fastaredux.sumAndScale(fastaredux.HomoSapiens);

    fastaredux.RepeatFasta.make(">ONE Homo sapiens alu\n", fastaredux.ALU, n * 2);
    fastaredux.RandomFasta.make(">TWO IUB ambiguity codes\n", fastaredux.IUB, n * 3);
    fastaredux.RandomFasta.make(">THREE Homo sapiens frequency\n", fastaredux.HomoSapiens, n * 5);
    fastaredux.Out.close();
}