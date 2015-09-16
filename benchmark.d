import std.c.process;

import std.stdio;
import std.conv;
import std.datetime;
import std.file;
import std.path;
import std.array;
import std.algorithm;
import std.regex;
import std.string;
import std.typecons;
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
        try {
            execute( command[ 0 ] );
            Config.registerCompiler( extension, this );
        } catch( ProcessException e ) {
            writeln( "disabled ", id, " because it is not available" );
        }
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
    shared static this() {
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

    struct ProcTableEntries
    {
        public:
            void setValues( string id, string[] values )
            {
                valuesPerId[ id ] = values;
            }

            T value( T = string )( string id = valuesPerId.keys[ 0 ], int columnIdx = 0 )
            {
                static if( is( typeof( T ) == string ) )
                {
                    return valuesPerId[ id ][ columnIdx ];
                }
                return to!T( valuesPerId[ id ][ columnIdx ] );
            }

            string[] values( string id )
            {
                return valuesPerId[ id ];
            }

            bool contains( string id )
            {
                return valuesPerId.keys().canFind( id );
            }

        private:
            string[][ string ] valuesPerId;
    }

    alias Tuple!( string, "id",
                  int, "lineIdx",
                  int, "columnIdx" ) ProcTableCell;

    private static ProcTableEntries getProcTableEntries(
                                string procPath )
    {
        ProcTableEntries entries;
        foreach( line; File( procPath, "r" ).byLine() )
        {
            auto rowSplit = line.split( ':' );
            string rowId;
            string[] values;
            if( rowSplit.length > 1 )
            {
                rowId = to!string( rowSplit[ 0 ] );
                values = to!( string[] )( rowSplit[ 1 ].strip().split( regex( `\s+` ) ) );
            }
            else
            {
                rowSplit = split( line, regex( `\s+` ) );
                rowId = to!string( rowSplit[ 0 ] );
                values = to!( string[] )( rowSplit[ 1..$ ] );
            }
            entries.setValues( rowId, values );
        }
        return entries; 
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

    alias Tuple!( double, "utime", double, "stime" ) CpuTimes;
    alias Tuple!( int, "status",
                  int[], "cpuLoad",
                  double, "elapsedSecs",
                  double, "cpuSecs",
                  ulong, "memory" ) MeasureResults;

    version( linux )
    {
        import core.sys.posix.signal: SIGKILL, SIGTERM;
        
        shared static this()
        {
            TERM_SIGNAL = SIGTERM;
            KILL_SIGNAL = SIGKILL;

            // Check if proc table of status has proper form.
            ProcTableEntries entries = getProcTableEntries( "/proc/1/status" );

            assert( entries.contains( "Pid" ) &&
                    entries.contains( "PPid" ) &&
                    entries.contains( "VmHWM" ) &&
                    entries.value( "VmHWM", 1 ).startsWith( "kB" ) );

            // Check if proc table of stat has proper form.
            entries = getProcTableEntries( "/proc/stat" );
            // Support for Linux 2.6.0 and above
            assert( entries.contains( "cpu" ) &&
                    entries.contains( "cpu0" ) );
            assert( entries.values( "cpu" ).length == 10 &&
                    entries.values( "cpu0" ).length == 10 );
        }

        private Cpu[] cpuTimesPerCore()
        {
            ProcTableEntries entries = getProcTableEntries( "/proc/stat" );
            Cpu[] cpus;
            string id;
            int i = 0;
            while( entries.contains( ( id = "cpu" ~ to!string( i++ ) ) ) )
            {
                ulong totalPerCPU = 0;
                foreach( int j; 0 .. 7 )
                {
                    totalPerCPU += entries.value!ulong( id, j );
                }
                ulong idle = entries.value!ulong( id, 3 );
                idle += entries.value!ulong( id, 4 );
                cpus ~= [ Cpu( idle, totalPerCPU ) ];
            }
            return cpus;
        }

        private CpuTimes getCpuTimes()
        {
            import core.sys.posix.unistd;
            import core.sys.posix.sys.resource;
            rusage usage;
            getrusage( RUSAGE_CHILDREN, &usage );
            double utime = usage.ru_utime.tv_sec * 1_000_000 +
                         usage.ru_utime.tv_usec;
            double stime = usage.ru_stime.tv_sec * 1_000_000 +
                         usage.ru_stime.tv_usec;
            return CpuTimes( utime, stime );
        }

        private ulong maxMemoryForProcess( Pid pid )
        {
            ulong memory = 0;
            auto entries = dirEntries( "/proc", SpanMode.shallow, false );
            foreach( string name; entries )
            {
                immutable pidString = baseName( name );
                if( name.exists && name.isDir && pidString.isNumeric )
                {
                    int currentPid = to!int( pidString );
                    string procPath = name ~ "/status";
                    int ppid = getProcTableEntries( procPath ).value!int( "PPid", 0 );

                    if( currentPid == pid.processID || ppid == pid.processID )
                    {
                        memory += getProcTableEntries( procPath ).value!ulong( "VmHWM", 0 );
                    }
                }
            }
            return memory;
        }

        private int getTermTimeoutStatus()
        {
            return -TERM_SIGNAL;
        }

        private int getKillTimeoutStatus()
        {
            return -KILL_SIGNAL;
        }

        private MeasureResults measure( string[] cmd,
                              File processIn,
                              File processOut )
        {
            Cpu[] cpu0 = cpuTimesPerCore();
            CpuTimes cpuTimes0 = getCpuTimes();
            StopWatch sw;
            sw.start();
            Pid pid = spawnProcess( cmd, processIn, processOut, stderr );
            auto watchTask = task( &watch, pid );
            watchTask.executeInNewThread();
            int status = wait( pid );
            sw.stop();
            CpuTimes cpuTimes1 = getCpuTimes();
            Cpu[] cpu1 = cpuTimesPerCore();
            MeasureResults mr;
            mr.cpuLoad = cpuLoadPerCore( cpu0, cpu1 );
            mr.elapsedSecs = sw.peek().to!( "seconds", double )();
            mr.cpuSecs = ( ( cpuTimes1.utime - cpuTimes0.utime ) +
                           ( cpuTimes1.stime - cpuTimes0.stime ) ) /
                           1_000_000;
            mr.memory = watchTask.yieldForce();
            return mr;
        }
    }
    else version( Windows )
    {
        import win32.windef;
        import win32.winnt;
        import win32.winbase;

        shared static this()
        {
            TERM_SIGNAL = 1;
            KILL_SIGNAL = 2;
        }

        private Cpu[] cpuTimesPerCore()
        {
            Cpu[] cpus;
            return cpus;
        }

        private long getMemory( HANDLE jobHandle )
        {
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION ExtendedInfo;
            QueryInformationJobObject( jobHandle,
                                       JOBOBJECTINFOCLASS.JobObjectExtendedLimitInformation,
                                       &ExtendedInfo,
                                       JOBOBJECT_EXTENDED_LIMIT_INFORMATION.sizeof,
                                       NULL);
            return ExtendedInfo.PeakJobMemoryUsed / 1024;
        }

        private double getCpuTimes( HANDLE jobHandle )
        {
            JOBOBJECT_BASIC_ACCOUNTING_INFORMATION BasicInfo;
            QueryInformationJobObject( jobHandle,
                                       JOBOBJECTINFOCLASS.JobObjectBasicAccountingInformation,
                                       &BasicInfo,
                                       JOBOBJECT_BASIC_ACCOUNTING_INFORMATION.sizeof,
                                       NULL);
            double userTime = cast( double )BasicInfo.TotalUserTime.QuadPart / 10_000_000;
            double kernelTime = cast( double )BasicInfo.TotalKernelTime.QuadPart / 10_000_000;
            return userTime + kernelTime;
        }

        private ulong maxMemoryForProcess( Pid pid )
        {
            return 0;
        }

        private int getTermTimeoutStatus()
        {
            return TERM_SIGNAL;
        }

        private int getKillTimeoutStatus()
        {
            return KILL_SIGNAL;
        }

        private MeasureResults measure( string[] cmd,
                              File processIn,
                              File processOut )
        {
            MeasureResults mr;
            Cpu[] cpu0 = cpuTimesPerCore();
            StopWatch sw;
            sw.start();
            Pid pid = spawnProcess( cmd, processIn, processOut, stderr );
            auto watchTask = task( &watch, pid );
            watchTask.executeInNewThread();
            HANDLE jobHandle = CreateJobObject( NULL, NULL );
            AssignProcessToJobObject( jobHandle, pid.osHandle() );
            int status = wait( pid );
            sw.stop();
            mr.cpuSecs = getCpuTimes( jobHandle );
            mr.memory = getMemory( jobHandle );
            CloseHandle( jobHandle );
            Cpu[] cpu1 = cpuTimesPerCore();
            mr.cpuLoad = cpuLoadPerCore( cpu0, cpu1 );
            mr.elapsedSecs = sw.peek().to!( "seconds", double )();
            return mr;
        }
    }
    else version( OSX )
    {
        static assert( 0, "OSX not yet supported." );
    }
    else
    {
        static assert( 0, "Unsupported OS" );
    }

    private int[] cpuLoadPerCore( Cpu[] cpu0, Cpu[] cpu1 )
    {
        int[] cpuLoadPerCore;
        for( int i = 0; i < cpu0.length; i++ )
        {
            float idleDelta = cpu1[ i ].idle - cpu0[ i ].idle;
            ulong totalDelta = cpu1[ i ].total - cpu0[ i ].total;
            int cpuLoad = roundTo!int( 100 * ( 1.0 - idleDelta / totalDelta ) );
            cpuLoadPerCore ~= cpuLoad;
        }
        return cpuLoadPerCore;
    }

    private ulong watch( Pid pid )
    {
        ulong termTimeout = 5 * 60;
        ulong killTimeout = termTimeout + 30;
        StopWatch timeoutWatch;
        timeoutWatch.start();
        auto child = tryWait( pid );
        ulong maxMemory;
        while( !child.terminated )
        {
            StopWatch sw;
            sw.start();
            maxMemory = max( maxMemoryForProcess( pid ), maxMemory );
            sw.stop();
            bool isTermTimeout = timeoutWatch.peek().seconds() >= termTimeout;
            bool isKillTimeout = timeoutWatch.peek().seconds() >= killTimeout;
            long sleepTime = 200 - sw.peek().msecs();
            if( isTermTimeout && !isKillTimeout )
            {
                kill( pid, TERM_SIGNAL );
            }
            if( isKillTimeout )
            {
                kill( pid, KILL_SIGNAL );
            }
            if( sleepTime > 0 )
            {
                core.thread.Thread.sleep( dur!( "msecs" )( sleepTime ) );
            }
            child = tryWait( pid );
        }
        return maxMemory;
    }

    private void benchmark( string[] cmd,
                            string depInputFile = "",
                            string compilerOutputFile = "",
                            string benchmarkOutputFile = "" )
    {
        auto processIn = stdin;
        auto processOut = stdout;
        if( !depInputFile.empty )
        {
            processIn = File( depInputFile, "r" );
        }
        if( !compilerOutputFile.empty )
        {
            processOut = File( compilerOutputFile, "w" );
        }
        scope( exit )
        {
            if( !depInputFile.empty )
            {
                processIn.close();
            }
            if( !compilerOutputFile.empty )
            {
                processOut.close();
            }
        }

        MeasureResults mr = measure( cmd, processIn, processOut );

        if( mr.status == 0 )
        {
            if( !compilerOutputFile.empty && !benchmarkOutputFile.exists )
            {
                copy( compilerOutputFile, benchmarkOutputFile );
            }
            writeln( "~ CPU Load: " ~ to!string( mr.cpuLoad ) );
            writefln( "Elapsed seconds: %.2f[s]",
                      mr.elapsedSecs );
            writefln( "CPU seconds: %.2f[s]", mr.cpuSecs );
            writeln( "Memory: " ~ to!string( mr.memory ) ~ "[kB]\n" );
        }
        else
        {
            if( mr.status == getTermTimeoutStatus() )
            {
                stderr.writeln( "Spawned process timed out and got killed. (terminate)\n" );
            }
            else if( mr.status == getKillTimeoutStatus() )
            {
                stderr.writeln( "Spawned process timed out and got killed. (kill)\n" );
            }
            else
            {
                stderr.writeln( "Spawned process failed.\n" );
                exit( 1 );
            }
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
            writeln( "[Compile ",
                     id,
                     " ",
                     compiler.id,
                     "]\n",
                     join( cmd, " " ) );
            benchmark( cmd );
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
                    string depInputFile;
                    if( dependency )
                    {
                        depInputFile = buildPath( benchmarkOutputDir,
                                                         dependency.id ~
                                                         "_" ~
                                                         argument ~
                                                         ".txt" );
                        /* runCommand ~= "<" ~ depInputFile; */
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
                    write( "[Execute ",
                           id,
                           " ",
                           compiler.id,
                           "]\n",
                           join( runCommand, " " ) );
                    if( dependency )
                    {
                        write( " < " ~ depInputFile );
                    }
                    writeln();
                    benchmark( runCommand,
                               depInputFile,
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
    shared static string s_workingDir;
    shared static int TERM_SIGNAL;
    shared static int KILL_SIGNAL;
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
    static void initializeConfig()
    {
        auto compiler = new Compiler( "dmd2.064",
                                      "d",
                                    [ "dmd",
                                      "-O",
                                      "-release",
                                      "-inline",
                                      "-noboundscheck" ] );
        compiler = new Compiler( "ldc0.13.0",
                                  "d",
                                [ "ldmd2",
                                  "-O",
                                  "-release",
                                  "-inline",
                                  "-noboundscheck" ] );
        compiler = new Compiler( "gdc4.8.2",
                                  "d",
                                [ "gdmd",
                                  "-O",
                                  "-release",
                                  "-inline",
                                  "-noboundscheck" ] );

        compiler = new Compiler( "javac1.7.0_55",
                                  "java",
                                [ "javac",
                                  "-d", 
                                  "$compilerBuildDir" ] );

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

    static void registerCompiler( string extension, Compiler compiler )
    {
        s_compilersPerExtension[ extension ] ~= compiler;
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
    Config.initializeConfig();
    Benchmark[] benchmarks = Config.initializeBenchmarks( args );
    rmdirRecurseIfExists( "./build" );
    rmdirRecurseIfExists( "./output" );
    foreach( benchmark; benchmarks )
    {
        benchmark.compile();
        benchmark.run();
    }
}

