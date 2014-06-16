#!/usr/bin/env rdmd

import std.c.process;

import std.stdio;
import std.file;
import std.path;
import std.array;
import std.algorithm;
import std.regex;
import std.string;
import std.process;


struct Config
{
    struct Compiler
    {
        string m_id;
        string m_extension;
        string[] m_command;

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
    }

    static Compiler[][ string ] s_compilersPerExtension;

    static this()
    {
        s_compilersPerExtension[ "d" ] = [ 
            Compiler( "dmd2.064", "d",
                      [ "dmd", "-O", "-release", "-inline" ] ),
            Compiler( "ldc0.12.0", "d",
                      [ "ldmd2", "-O", "-release", "-inline" ] ),
            Compiler( "gdc4.8.2", "d",
                      [ "gdmd", "-O", "-release", "-inline" ] )
        ];
        s_compilersPerExtension[ "java" ] = [
            Compiler( "javac1.7.0_55", "java",
                      [ "javac", "-d", "$compilerBuildDir" ] )
        ];
    }

    static @property Compiler[] compilersPerExtension( string extension )
    {
        Compiler[] compilers;
        if( extension in s_compilersPerExtension )
        {
            compilers = s_compilersPerExtension[ extension ];
        }
        return compilers;
    }
}

void compile( string extension, string buildDir,
              string workingDir, string path )
{
    immutable srcFile = buildNormalizedPath( workingDir, path );
    foreach( compiler; Config.compilersPerExtension( extension ) )
    {
        immutable compilerBuildDir = buildPath( buildDir, compiler.id );
        if( !exists( compilerBuildDir ) )
        {
            mkdirRecurse( compilerBuildDir );
        }
        chdir( compilerBuildDir );
        string[] cmd = compiler.command ~ srcFile;
        foreach( ref element; cmd )
        {
            element = element.replace( "$compilerBuildDir", compilerBuildDir );
        }
        writeln( "[Compile with ", compiler.id, "]\n", join( cmd, " " ) );
        auto result = execute( cmd );
        if( result.status !=  0 )
        {
            stderr.writeln( "Compilation failed:\n", result.output );
            exit( 1 );
        }
    }
}

void main( string[] args )
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
	if( args.length > 1 )
	{
		auto intersection = setDifference(  benchmarks.keys.sort,
                                            args[ 1 .. $ ].sort );
		foreach( name; intersection )
		{
			benchmarks.remove( name );
		}
	}
    if( exists( "./build" ) )
    {
        rmdirRecurse( "./build" );
    }
    immutable workingDir = getcwd();
	foreach( name; benchmarks.keys )
	{
        foreach( path; benchmarks[ name ] )
        {
            immutable relBuildDir = replaceFirst( dirName( path ),
                                                  "./src",
                                                  "./build" );
            immutable buildDir = buildNormalizedPath( workingDir, relBuildDir );
            compile( extension( path )[ 1 .. $ ], buildDir, workingDir, path );
        }
	}
	return;
}

