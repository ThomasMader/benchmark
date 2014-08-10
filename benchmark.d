#!/usr/bin/env rdmd

import std.c.process;

import core.thread;
import core.stdc.config;
import core.sys.posix.unistd;

import std.stdio;
import std.conv;
import std.datetime;
import std.file;
import std.path;
import std.array;
import std.algorithm;
import std.regex;
import std.string;
import std.parallelism;
import std.process;


class Compiler
{
public:
    this( string id, string extension, string[] command )
    {
        m_id = id;
        m_extension = extension;
        m_command = command;
    }

    @property string id()
    {
        return m_id;
    }

    @property string extension()
    {
        return m_extension;
    }

    @property string[] command()
    {
        return m_command;
    }

private:
    string m_id;
    string m_extension;
    string[] m_command;
}

class Benchmark
{
public:
    static this() {
        s_workingDir = getcwd();
    }

    this( string id,
          string[] arguments = [],
          Benchmark dependency = null,
          string[] dependencyArgs = [] )
    {
        m_id = id;
        m_arguments = arguments;
        m_dependency = dependency;
        m_dependencyArgs = dependencyArgs;
    }

    @property string id()
    {
        return m_id;
    }

    @property string[] files()
    {
        return m_files;
    }

    @property void files( string[] files )
    {
        m_files = files;
    }

    void filesCheck()
    {
        if( m_files.empty )
        {
            stderr.writeln( "Benchmark '", id(), "' has no source files." );
            exit( 1 );
        }
    }

    @property string[] arguments()
    {
        return m_arguments;
    }

    @property Benchmark dependency()
    {
        return m_dependency;
    }

    @property string[] dependencyArgs()
    {
        return m_dependencyArgs;
    }

    private string compilerDir( string type,
                                string srcFile,
                                Compiler compiler )
    {
        immutable string relDir = replaceFirst( dirName( srcFile ),
                                              "./src",
                                              "./" ~ type );
        immutable string dir = buildNormalizedPath( s_workingDir,
                                                    relDir );
        immutable string compilerDir = buildPath( dir,
                                                  compiler.id );
        if( !compilerDir.exists )
        {
            mkdirRecurse( compilerDir );
        }
        return compilerDir;
    }

    private bool executableExists( string dir, string name )
    {
        foreach( entry; dirEntries( dir, SpanMode.shallow ) )
        {
            if( isFile( entry ) && baseName( entry.name ).startsWith( name ) )
            {
                return true;
            }
        }
        return false;
    }

    private string[][] readProcTable( string procPath )
    {
        string[] procPerLine = split( readText( procPath ), "\n" );
        string[][] procTable;
        foreach( line; procPerLine )
        {
            procTable ~= split( line, regex( `\s+` ) );
        }
        return procTable;
    }

    private T getProcTableEntry( T )( string[][] procTable,
                                      int lineIdx,
                                      int columnIdx )
    {
        return to!T( procTable[ lineIdx ][ columnIdx ] );
    }

    struct Cpu
    {
    public:
        this( ulong idle, ulong total )
        {
            m_idle = idle;
            m_total = total;
        }

        @property ulong idle()
        {
            return m_idle;
        }

        @property ulong total()
        {
            return m_total;
        }

    private:
        ulong m_idle;
        ulong m_total;
    }

    private Cpu[] cpuTimesPerCore()
    {
        string[][] statTable = readProcTable( "/proc/stat" );
        // Support for Linux 2.6.0 and above
        assert( statTable[ 0 ].length >= 8 &&
                statTable[ 0 ][ 0 ].startsWith( "cpu" ) );
        ulong[] getProcCPUColumn( const int column )
        {
            ulong[] values;
            for( int i = 1;
                 statTable[ i ][ 0 ].startsWith( "cpu" );
                 i++ )
            {
                values ~= getProcTableEntry!( ulong )( statTable, i, column );
            }
            return values;
        }

        ulong[] userPerCPU = getProcCPUColumn( 1 );
        ulong[] nicePerCPU = getProcCPUColumn( 2 );
        ulong[] systemPerCPU = getProcCPUColumn( 3 );
        ulong[] idlePerCPU = getProcCPUColumn( 4 );
        ulong[] iowaitPerCPU = getProcCPUColumn( 5 );
        ulong[] irqPerCPU = getProcCPUColumn( 6 );
        ulong[] softirqPerCPU = getProcCPUColumn( 7 );
        Cpu[] cpus;
        foreach( i, user; userPerCPU )
        {
            ulong totalPerCPU = user +
                                nicePerCPU[ i ] +
                                systemPerCPU[ i ] +
                                idlePerCPU[ i ] +
                                iowaitPerCPU[ i ] +
                                irqPerCPU[ i ] +
                                softirqPerCPU[ i ];
            cpus ~= [ Cpu( idlePerCPU[ i ], totalPerCPU ) ];
        }
        return cpus;
    }

    private string cpuLoadPerCore( Cpu[] cpu0, Cpu[] cpu1 )
    {
        string cpuLoadPerCore;
        for( int i = 0; i < cpu0.length; i++ )
        {
            float idleDelta = cpu1[ i ].idle - cpu0[ i ].idle;
            ulong totalDelta = cpu1[ i ].total - cpu0[ i ].total;
            int cpuLoad = roundTo!int( 100 * ( 1.0 - idleDelta / totalDelta ) );
            cpuLoadPerCore ~= to!string( cpuLoad ) ~ "% ";
        }
        return cpuLoadPerCore;
    }

    private ulong maxMemoryForProcess( Pid p_pid )
    {
        string[][] statusTable = readProcTable( "/proc/1/status" );
        assert( statusTable[ 5 ][ 0 ].startsWith( "PPid" ) &&
                statusTable[ 5 ].length == 2 &&
                statusTable[ 4 ][ 0 ].startsWith( "Pid" ) &&
                statusTable[ 4 ].length == 2 &&
                statusTable[ 15 ][ 0 ].startsWith( "VmHWM" ) &&
                statusTable[ 15 ].length == 3 &&
                statusTable[ 15 ][ 2 ] == "kB" );
        ulong memory = 0;
        foreach( string name; dirEntries( "/proc", SpanMode.shallow ) )
        {
            if( name.isDir && baseName( name ).isNumeric )
            {
                statusTable = readProcTable( name ~ "/status" );
                ulong ppid = getProcTableEntry!( ulong )( statusTable, 5, 1 );
                ulong pid = getProcTableEntry!( ulong )( statusTable, 4, 1 );
                if( pid == p_pid.processID || ppid == p_pid.processID )
                {
                    memory += getProcTableEntry!( ulong )( statusTable, 15, 1 );
                }
            }
        }
        return memory;
    }

    private ulong measureMemory( Pid pid )
    {
        auto child = tryWait( pid );
        ulong maxMemory;
        while( !child.terminated )
        {
            maxMemory = max( maxMemoryForProcess( pid ), maxMemory );
            core.thread.Thread.sleep( dur!( "msecs" )( 200 ) );
            child = tryWait( pid );
        }
        return maxMemory;
    }

    private void measure( string[] cmd,
                          string compilerOutputFile = "",
                          string benchmarkOutputFile = "" )
    {
        Cpu[] cpu0 = cpuTimesPerCore();
        string procUptime = "/proc/uptime";
        string procStat = "/proc/" ~ to!string( thisProcessID() ) ~ "/stat";
        StopWatch sw;
        sw.start();
        auto pipes = pipeProcess( cmd, Redirect.stdout | Redirect.stderr );
        auto memoryTask = task( &measureMemory, pipes.pid );
        memoryTask.executeInNewThread();
        int status = wait( pipes.pid );
        sw.stop();
        if( status == 0 )
        {
            Cpu[] cpu1 = cpuTimesPerCore();
            /* c_long hertz = sysconf( _SC_CLK_TCK ); */
            writeln( "Memory: " ~ to!string( memoryTask.yieldForce ) ~ "[kB]" );
            writeln( "~ CPU Load: " ~ cpuLoadPerCore( cpu0, cpu1 ) );
            writeln( "Execution time: ",
                     sw.peek().msecs,
                     "[ms]\n" );
            if( !compilerOutputFile.empty && !benchmarkOutputFile.empty )
            {
                string output;
                foreach( line; pipes.stdout.byLine )
                {
                    output ~= line.idup ~ "\n";
                }
                std.file.write( compilerOutputFile, output );
                if( !benchmarkOutputFile.exists )
                {
                    copy( compilerOutputFile, benchmarkOutputFile );
                }
            }
        }
        else
        {
            foreach( line; pipes.stderr.byLine )
            {
                stderr.writeln( line.idup );
            }
            stderr.writeln( "Spawned process failed.\n" );
            exit( 1 );
        }
    }

    private void compile( Compiler compiler,
                          string extension,
                          string srcFile,
                          string compilerBuildDir,
                          string compilerOutputDir,
                          Benchmark dependentBenchmark )
    {
        if( !executableExists( compilerBuildDir,
                               stripExtension( baseName( srcFile ) ) ) )
        {
            string[] cmd = compiler.command ~ srcFile;
            foreach( ref element; cmd )
            {
                element = element.replace( "$compilerBuildDir", compilerBuildDir );
            }
            chdir( compilerBuildDir );
            writeln( "[",
                     id,
                     " ",
                     compiler.id,
                     " Compilation]\n",
                     join( cmd, " " ) );
            measure( cmd );
        }
    }

    private void run( Compiler compiler,
                      string extension,
                      string srcFile,
                      string compilerBuildDir,
                      string compilerOutputDir,
                      Benchmark dependentBenchmark )
    {
        string benchmarkOutputDir = buildPath( s_workingDir,
                                               "output" );
        string[] runCommand = Config.runCommandPerExt( extension );
        if( !runCommand.empty )
        {
            string name = stripExtension( baseName( srcFile ) );
            foreach( ref element; runCommand )
            {
                element = element.replace( "$name", name );
            }
            string[] args = arguments;
            if( dependency )
            {
                args = dependencyArgs;
            }
            if( dependentBenchmark )
            {
                args = dependentBenchmark.dependencyArgs;
            }
            foreach( argument; args )
            {
                string outputFileName;
                if( dependency )
                {
                    outputFileName = id ~
                                     "-" ~
                                     dependency.id ~
                                     "_" ~
                                     argument ~
                                     ".txt";
                }
                else
                {
                    outputFileName = id ~ "_" ~ argument ~ ".txt";
                }
                string benchmarkOutputFile = buildPath( benchmarkOutputDir,
                                                        outputFileName );
                if( ( dependentBenchmark && !benchmarkOutputFile.exists ) ||
                    dependentBenchmark is null )
                {
                    string compilerOutputFile = buildPath( compilerOutputDir,
                                                           outputFileName );
                    if( dependency )
                    {
                        string depInputFile = buildPath( benchmarkOutputDir,
                                                         dependency.id ~
                                                         "_" ~
                                                         argument ~
                                                         ".txt" );
                        runCommand ~= "<" ~ depInputFile;
                        if( !depInputFile.exists )
                        {
                            dependency.compile( this );
                            dependency.run( this );
                        }
                    }
                    else
                    {
                        runCommand ~= argument;
                    }
                    chdir( compilerBuildDir );
                    writeln( "[",
                             id,
                             " ",
                             compiler.id,
                             " Execution]\n",
                             join( runCommand, " " ) );
                    measure( runCommand,
                             compilerOutputFile,
                             benchmarkOutputFile );
                }
            }
        }
    }

    private void compileOrRun( Benchmark dependentBenchmark,
                               void delegate( Compiler,
                                              string,
                                              string,
                                              string,
                                              string,
                                              Benchmark ) dg )
    {
        foreach( file; files )
        {
            string extension = extension( file )[ 1 .. $ ];
            string srcFile = buildNormalizedPath( s_workingDir, file );
            foreach( compiler; Config.compilersPerExt( extension ) )
            {
                string compilerBuildDir = compilerDir( "build",
                                                       file,
                                                       compiler );
                string compilerOutputDir = compilerDir( "output",
                                                        file,
                                                        compiler );
                dg( compiler,
                    extension,
                    srcFile,
                    compilerBuildDir,
                    compilerOutputDir,
                    dependentBenchmark );
                if( dependentBenchmark )
                {
                    return;
                }
            }
        }
    }

    void compile( Benchmark dependentBenchmark = null )
    {
        compileOrRun( dependentBenchmark, &compile );
    }

    void run( Benchmark dependentBenchmark = null )
    {
        compileOrRun( dependentBenchmark, &run );
    }
private:
    static string s_workingDir;
    string m_id;
    string[] m_files;
    string[] m_arguments;
    Benchmark m_dependency;
    string[] m_dependencyArgs;
    alias m_id this;
}

struct Config
{
public:
    static this()
    {
        s_compilersPerExtension[ "d" ] = [ 
            new Compiler( "dmd2.064",
                          "d",
                          [ "dmd",
                            "-O",
                            "-release",
                            "-inline",
                            "-noboundscheck" ] ),
            new Compiler( "ldc0.13.0",
                          "d",
                          [ "ldmd2",
                            "-O",
                            "-release",
                            "-inline",
                            "-noboundscheck" ] ),
            new Compiler( "gdc4.8.2",
                          "d",
                          [ "gdmd",
                            "-O",
                            "-release",
                            "-inline",
                            "-noboundscheck" ] )
        ];

        s_compilersPerExtension[ "java" ] = [
            new Compiler( "javac1.7.0_55",
                          "java",
                          [ "javac",
                            "-d", 
                            "$compilerBuildDir" ] )
        ];

        s_runCommandPerExtension[ "d" ] = [ "./$name" ];

        s_runCommandPerExtension[ "java" ] = [ "java",
                                               "-server",
                                               "-XX:+TieredCompilation",
                                               "-XX:+AggressiveOpts",
                                               "$name" ];

        s_benchmarkPerName[ "binarytrees" ] = new Benchmark(
                                                "binarytrees",
                                                [ "20" ] );

        s_benchmarkPerName[ "binarytreesredux" ] = new Benchmark(
                                                "binarytreesredux",
                                                [ "20" ] );

        s_benchmarkPerName[ "mandelbrot" ] = new Benchmark(
                                                "mandelbrot",
                                                [ "16000" ] );

        s_benchmarkPerName[ "fasta" ] = new Benchmark(
                                                "fasta",
                                                [ "25000000" ] );

        s_benchmarkPerName[ "knucleotide" ] = new Benchmark(
                                                "knucleotide",
                                                [ "0" ],
                                                s_benchmarkPerName[ "fasta" ],
                                                [ "25000000" ] );

        s_benchmarkPerName[ "fastaredux" ] = new Benchmark(
                                                "fastaredux",
                                                [ "25000000" ] );

        s_benchmarkPerName[ "fannkuchredux" ] = new Benchmark(
                                                "fannkuchredux",
                                                [ "12" ] );

        s_benchmarkPerName[ "chameneosredux" ] = new Benchmark(
                                                "chameneosredux",
                                                [ "6000000" ] );

        s_benchmarkPerName[ "meteor" ] = new Benchmark(
                                                "meteor",
                                                [ "2098" ] );

        s_benchmarkPerName[ "nbody" ] = new Benchmark(
                                                "nbody",
                                                [ "50000000" ] );

        s_benchmarkPerName[ "pidigits" ] = new Benchmark(
                                                "pidigits",
                                                [ "10000" ] );

        s_benchmarkPerName[ "regexdna" ] = new Benchmark(
                                                "regexdna",
                                                [ "0" ],
                                                s_benchmarkPerName[ "fasta" ],
                                                [ "5000000" ] );

        s_benchmarkPerName[ "revcomp" ] = new Benchmark(
                                                "revcomp",
                                                [ "0" ],
                                                s_benchmarkPerName[ "fasta" ],
                                                [ "25000000" ] );

        s_benchmarkPerName[ "spectralnorm" ] = new Benchmark(
                                                "spectralnorm",
                                                [ "5500" ] );

        s_benchmarkPerName[ "threadring" ] = new Benchmark(
                                                "threadring",
                                                [ "50000000" ] );
    }

    static Benchmark[] initializeBenchmarks( string[] args )
    {
        auto files = dirEntries( "./src", SpanMode.depth );
        string[][ string ] benchmarks;
        foreach( file; files )
        {
            if( isFile( file ) ) {
                string name = split( stripExtension( baseName( file.name ) ), 
                                                     regex( "_[0-9]+$" ) )[0];
                benchmarks[ name ] ~= file.name;
            }
        }
        foreach( name; benchmarks.keys )
        {
            Benchmark benchmark;
            if( name in s_benchmarkPerName )
            {
                benchmark = s_benchmarkPerName[ name ];
                benchmark.files( benchmarks[ name ] );
            }
        }
        if( args.length > 1 )
        {
            auto intersection = setDifference(  benchmarks.keys.sort,
                                                args[ 1 .. $ ].sort );
            foreach( name; intersection )
            {
                benchmarks.remove( name );
            }
        }
        Benchmark[] benchmarksOrderedByDependency;
        foreach( name; benchmarks.keys )
        {
            Benchmark benchmark;
            if( name in s_benchmarkPerName )
            {
                benchmark = s_benchmarkPerName[ name ];
                if( !canFind( benchmarksOrderedByDependency, benchmark ) )
                {
                    benchmark.filesCheck();
                    Benchmark dependency = benchmark.dependency;
                    while( dependency )
                    {
                        dependency.filesCheck();
                        if( dependency in benchmarks )
                        {
                            benchmarksOrderedByDependency ~= dependency;
                        }
                        dependency = dependency.dependency;
                    }
                    benchmarksOrderedByDependency ~= benchmark;
                }
            }
            else
            {
                stderr.writeln( "Unknown Benchmark: ", name );
                exit( 1 );
            }
        }
        return benchmarksOrderedByDependency;
    }

    static Compiler[] compilersPerExt( string extension )
    {
        Compiler[] compilers;
        if( extension in s_compilersPerExtension )
        {
            compilers = s_compilersPerExtension[ extension ];
        }
        return compilers;
    }

    static string[] runCommandPerExt( string extension )
    {
        string[] runCommand;
        if( extension in s_runCommandPerExtension )
        {
            runCommand = s_runCommandPerExtension[ extension ].dup;
        }
        return runCommand;
    }
private:
    static Compiler[][ string ] s_compilersPerExtension;
    static Benchmark[ string ] s_benchmarkPerName;
    static string[][ string ] s_runCommandPerExtension;
}

void rmdirRecurseIfExists( immutable string dir )
{
    if( dir.exists )
    {
        rmdirRecurse( dir );
    }
}

void main( string[] args )
{
    Benchmark[] benchmarks = Config.initializeBenchmarks( args );
    rmdirRecurseIfExists( "./build" );
    rmdirRecurseIfExists( "./output" );
    foreach( benchmark; benchmarks )
    {
        benchmark.compile();
        benchmark.run();
    }
}

