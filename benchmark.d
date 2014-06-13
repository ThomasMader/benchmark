#!/usr/bin/env rdmd

import std.stdio;
import std.file;
import std.path;
import std.array;
import std.algorithm;
import std.regex;
import std.process;

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
	string[] dmdCommand = [ "dmd", "-O", "-release", "-inline" ];
	string[] javacCommand = [ "javac" ];
	bool doJavac = execute( javacCommand ~ "-version" ).status == 0;
    if( exists( "./build" ) )
    {
        rmdirRecurse( "./build" );
    }
    immutable workingDir = getcwd();
	foreach( name; benchmarks.keys )
	{
        foreach( path; benchmarks[ name ] )
        {
            immutable buildDir = absolutePath( replaceFirst( dirName( path ),
                                                             "./src",
                                                             "./build" ) );
            if( !exists( buildDir ) )
            {
                mkdirRecurse( buildDir );
            }

            void executeCommand( string[] command )
            {
                auto cmd = execute( command ~ buildPath( workingDir, path ) );
                if( cmd.status !=  0 )
                {
                    writeln( "Compilation failed:\n", cmd.output );
                    return;
                }
            }
            void delegate( string[] command ) commandDG = &executeCommand;

            if( extension( path ) == ".d" )
            {
                chdir( buildDir );
                commandDG( dmdCommand );
                chdir( workingDir );
            }
            else if( extension( path ) == ".java" )
            {
                commandDG( javacCommand ~ "-d" ~ buildDir );
            }
        }
	}
	return;
}

