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

    struct ProcTableEntries
    {
        public:
            void appendToValue( string p_id, char p_char )
            {
                valuesPerId[ p_id ] ~= p_char;
            }

            T value( T = string )( string p_id = valuesPerId.keys[ 0 ] )
            {
                static if( is( typeof( T ) == string ) )
                {
                    return valuesPerId[ p_id ];
                }
                return to!T( valuesPerId[ p_id ] );
            }

        private:
            string[ string ] valuesPerId;
    }

    alias Tuple!( string, "id",
                  int, "lineIdx",
                  int, "columnIdx" ) ProcTableCell;

    private T getProcTableEntry( T = string )( string procPath,
                                               int lineIdx,
                                               int columnIdx )
    {
        return getProcTableEntries( procPath,
                                    [ ProcTableCell( "",
                                                     lineIdx,
                                                     columnIdx )
                                    ] ).value!T( "" );
    }

    private ProcTableEntries getProcTableEntries( string procPath )
    {
        return getProcTableEntries( procPath,
                                    [ ProcTableCell( "",
                                                     -1,
                                                     -1 )
                                    ] );
    }

    private ProcTableEntries getProcTableEntries(
                                string procPath,
                                ProcTableCell[] p_cells )
    {
        import std.ascii;
        ProcTableEntries entries;
        bool inWhite = false;
        int i = 0;
        int j = 0;
        multiSort!( "a[1] < b[1]", "a[2] < b[2]" )( p_cells );
        auto currentCell = p_cells.front;
        p_cells.popFront;
        bool allLines = currentCell.lineIdx < 0 ? true : false;
        bool allColumns = currentCell.columnIdx < 0 ? true : false;
        foreach( ubyte[] c; File( procPath, "r" ).byChunk( 1 ) )
        {
            if( !allLines || !allColumns )
            {
                if( ( i > currentCell.lineIdx && !allLines ) ||
                    ( i >= currentCell.lineIdx &&
                        ( j > currentCell.columnIdx && !allColumns ) ) )
                {
                    if( !p_cells.empty )
                    {
                        currentCell = p_cells.front;
                        p_cells.popFront;
                    }
                    else
                    {
                        break;
                    }
                }
            }
            if( c == newline )
            {
                i++;
                j = 0;
                continue;
            }
            if( currentCell.lineIdx == i || allLines )
            {
                if( c[ 0 ].isWhite() )
                {
                    inWhite = true;
                    continue;
                }
                if( inWhite )
                {
                    inWhite = false;
                    j++;
                }
                if( currentCell.columnIdx == j || allColumns )
                {
                    if( allLines || allColumns )
                    {
                        entries.appendToValue( to!string( i ) ~
                                               "," ~
                                               to!string( j ),
                                               c[ 0 ] );
                    }
                    else
                    {
                        entries.appendToValue( currentCell.id, c[ 0 ] );
                    }
                }
            }
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

    version( linux )
    {
        import core.sys.posix.signal: SIGKILL, SIGTERM;

        private Cpu[] cpuTimesPerCore()
        {
            ProcTableEntries entries = getProcTableEntries( "/proc/stat" );
            // Support for Linux 2.6.0 and above
            assert( entries.value( "0,0" ) == "cpu" &&
                    entries.value( "1,0" ) == "cpu0" );
            Cpu[] cpus;
            string line;
            for( int i = 1;
                 entries.value( ( line = to!string( i ) ) ~ ",0" ).startsWith( "cpu" );
                 i++ )
            {
                ulong totalPerCPU = 0;
                foreach( int j; 1 .. 8 )
                {
                    string column = to!string( j );
                    totalPerCPU += entries.value!ulong( line ~ "," ~ column );
                }
                ulong idle = entries.value!ulong( line ~ ",4" );
                cpus ~= [ Cpu( idle, totalPerCPU ) ];
            }
            return cpus;
        }

        private ulong measureMemory( Pid pid )
        {
            ProcTableCell[] tableCells =
            [   
                ProcTableCell( "Pid", 4, 0 ),
                ProcTableCell( "PPid", 5, 0 ),
                ProcTableCell( "VmHWM", 15, 0 ),
                ProcTableCell( "kB", 15, 2 )
            ];
            ProcTableEntries entries = getProcTableEntries( "/proc/1/status",
                                                            tableCells );
            assert( entries.value( "Pid" ).startsWith( "Pid" ) &&
                    entries.value( "PPid" ).startsWith( "PPid" ) &&
                    entries.value( "VmHWM" ).startsWith( "VmHWM" ) &&
                    entries.value( "kB" ).startsWith( "kB" ) );
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
                    kill( pid, SIGTERM );
                }
                if( isKillTimeout )
                {
                    kill( pid, SIGKILL );
                }
                if( sleepTime > 0 )
                {
                    core.thread.Thread.sleep( dur!( "msecs" )( sleepTime ) );
                }
                child = tryWait( pid );
            }
            return maxMemory;
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

        private int getKillTimeoutSignal()
        {
            return -SIGKILL;
        }
    }
    else version( Windows )
    {
        import win32.windef;
        import win32.winnt;
        import win32.winbase;


        private Cpu[] cpuTimesPerCore()
        {
            Cpu[] cpus;
            return cpus;
        }

        private ulong measureMemory( Pid pid )
        {
            return 0;
        }

        private double getCpuTimes( HANDLE p_jobHandle )
        {
            JOBOBJECT_BASIC_ACCOUNTING_INFORMATION BasicInfo;
            QueryInformationJobObject( p_jobHandle,
                                       JOBOBJECTINFOCLASS.JobObjectBasicAccountingInformation,
                                       &BasicInfo,
                                       JOBOBJECT_BASIC_ACCOUNTING_INFORMATION.sizeof,
                                       NULL);
            double userTime = cast( double )BasicInfo.TotalUserTime.QuadPart / 10_000_000;
            double kernelTime = cast( double )BasicInfo.TotalKernelTime.QuadPart / 10_000_000;
            return userTime + kernelTime;
        }

        private int getKillTimeoutSignal()
        {
            return 0;
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
        ulong memory = 0;
        auto entries = dirEntries( "/proc", SpanMode.shallow, false );
        foreach( string name; entries )
        {
            immutable pidString = baseName( name );
            if( name.exists && name.isDir && pidString.isNumeric )
            {
                int pid = to!int( pidString );
                string procPath = name ~ "/status";
                int ppid = getProcTableEntry!int( procPath, 5, 1 );

                if( pid == p_pid.processID || ppid == p_pid.processID )
                {
                    memory += getProcTableEntry!ulong( procPath, 15, 1 );
                }
            }
        }
        return memory;
    }

    private void measure( string[] cmd,
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
        version( linux )
        {
            Cpu[] cpu0 = cpuTimesPerCore();
            CpuTimes cpuTimes0 = getCpuTimes();
            StopWatch sw;
            sw.start();
            Pid pid = spawnProcess( cmd, processIn, processOut, stderr );
            auto memoryTask = task( &measureMemory, pid );
            memoryTask.executeInNewThread();
            int status = wait( pid );
            sw.stop();
            CpuTimes cpuTimes1 = getCpuTimes();
            CpuTimes cpuTimes = CpuTimes( cpuTimes1.utime - cpuTimes0.utime,
                                          cpuTimes1.stime - cpuTimes0.stime );
            double cpuSecs = ( ( cpuTimes1.utime - cpuTimes0.utime ) +
                               ( cpuTimes1.stime - cpuTimes0.stime ) ) /
                                1_000_000;
            Cpu[] cpu1 = cpuTimesPerCore();
        }
        else version( Windows )
        {
            Cpu[] cpu0 = cpuTimesPerCore();
            StopWatch sw;
            sw.start();
            Pid pid = spawnProcess( cmd, processIn, processOut, stderr );
            HANDLE jobHandle = CreateJobObject( NULL, NULL );
            AssignProcessToJobObject( jobHandle, pid.osHandle() );
            auto memoryTask = task( &measureMemory, pid );
            memoryTask.executeInNewThread();
            int status = wait( pid );
            sw.stop();
            double cpuSecs = getCpuTimes( jobHandle );
            CloseHandle( jobHandle );
            Cpu[] cpu1 = cpuTimesPerCore();
        }
        if( status == 0 )
        {
            if( !compilerOutputFile.empty && !benchmarkOutputFile.exists )
            {
                copy( compilerOutputFile, benchmarkOutputFile );
            }
            writeln( "~ CPU Load: " ~ cpuLoadPerCore( cpu0, cpu1 ) );
            writefln( "Elapsed seconds: %.2f[s]",
                      sw.peek().to!( "seconds", double )() );
            writefln( "CPU seconds: %.2f[s]", cpuSecs );
            writeln( "Memory: " ~ to!string( memoryTask.yieldForce() ) ~ "[kB]\n" );
        }
        else
        {
            if( status == 143 )
            {
                stderr.writeln( "Spawned process timed out. (got terminated)\n" );
            }
            else if( status == getKillTimeoutSignal() )
            {
                stderr.writeln( "Spawned process timed out. (got killed)\n" );
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
                    measure( runCommand,
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

