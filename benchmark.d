#!/usr/bin/env rdmd

import std.c.process;

import std.stdio;
import std.datetime;
import std.file;
import std.path;
import std.array;
import std.algorithm;
import std.regex;
import std.string;
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
            StopWatch sw;
            sw.start();
            auto result = execute( cmd );
            sw.stop();
            if( result.status !=  0 )
            {
                stderr.writeln( "Compilation failed:\n", result.output );
                exit( 1 );
            }
            else
            {
                writeln( "Compilation time: ", sw.peek().msecs, "[ms]\n" );
            }
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
                    string compilerOutputfile = buildPath( compilerOutputDir,
                                                           outputFileName );
                    string command;
                    if( dependency )
                    {
                        string depInputFile = buildPath( benchmarkOutputDir,
                                                         dependency.id ~
                                                         "_" ~
                                                         argument ~
                                                         ".txt" );
                        command = join( runCommand ~ "<" ~ depInputFile, " " );
                        if( !depInputFile.exists )
                        {
                            dependency.compile( this );
                            dependency.run( this );
                        }
                    }
                    else
                    {
                        command = join( runCommand ~ argument, " " );
                    }
                    chdir( compilerBuildDir );
                    writeln( "[",
                             id,
                             " ",
                             compiler.id,
                             " Execution]\n",
                             command );
                    StopWatch sw;
                    sw.start();
                    auto result = executeShell( command );
                    sw.stop();
                    if( result.status !=  0 )
                    {
                        stderr.writeln( "Execution failed:\n", result.output );
                        exit( 1 );
                    }
                    else
                    {
                        writeln( "Execution time: ",
                                 sw.peek().msecs,
                                 "[ms]\n" );
                        std.file.write( compilerOutputfile, result.output );
                        if( !benchmarkOutputFile.exists )
                        {
                            copy( compilerOutputfile, benchmarkOutputFile );
                        }
                    }
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

