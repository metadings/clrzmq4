#!/usr/bin/env bash

#exit if any command fails
set -e

artifactsFolder="./artifacts"

if [ -d $artifactsFolder ]; then
  rm -R $artifactsFolder
fi

# TODO or use uname? what does that return on Mac OS?
if [ "$(sw_vers -productName)" == "Mac OS X" ] ; then
  # homebrew has zeromq only as x64 as of 2017-06-29, so we must use macports (see also https://github.com/travis-ci/travis-ci/issues/5640)
  #brew install zeromq --universal
  wget --retry-connrefused --waitretry=1 -O /tmp/macports.pkg https://github.com/macports/macports-base/releases/download/v2.4.1/MacPorts-2.4.1-10.11-ElCapitan.pkg
  sudo installer -pkg /tmp/macports.pkg -target /
  export PATH=/opt/local/bin:/opt/local/sbin:$PATH
  sudo rm /opt/local/etc/macports/archive_sites.conf
  echo "name macports_archives" >archive_sites.conf
  echo "name local_archives" >>archive_sites.conf
  echo "urls http://packages.macports.org/ http://nue.de.packages.macports.org/" >>archive_sites.conf
  sudo cp archive_sites.conf /opt/local/etc/macports/
  sudo port -v install zmq +universal || true # ignore errors, since this seems to always fail with "Updating database of binaries failed"
  sudo port -v install gtk-sharp2 || true # ignore errors, since this seems to always fail with "Updating database of binaries failed"
  file /usr/local/lib/*mq*.dylib
  file /opt/local/lib/*mq*.dylib
  find /usr/local -name '*zmq*' # DEBUG
  find /usr/local -name '*zeromq*' # DEBUG
  
  DYLD_LIBRARY_PATH=/opt/local/lib:$DYLD_LIBRARY_PATH
  echo LD_LIBRARY_PATH=$LD_LIBRARY_PATH
  echo DYLD_LIBRARY_PATH=$DYLD_LIBRARY_PATH
  echo DYLD_FALLBACK_LIBRARY_PATH=$DYLD_FALLBACK_LIBRARY_PATH
else  
  sudo apt-get install gtk-sharp2
fi

nuget install Mono.Options -Version 5.3.0.1
nuget install NUnit.ConsoleRunner -Version 3.6.1 -OutputDirectory testrunner
nuget install coveralls.net -Version 0.7.0 -OutputDirectory tools

pushd .
# TODO why is mono.cecil not simple installed using nuget? this example is from https://github.com/csMACnz/Coveralls.net-Samples/blob/xunit-monocov-travisci/.travis.yml
curl -sS https://api.nuget.org/packages/mono.cecil.0.9.5.4.nupkg > /tmp/mono.cecil.0.9.5.4.nupkg.zip
unzip /tmp/mono.cecil.0.9.5.4.nupkg.zip -d /tmp/cecil
cp /tmp/cecil/lib/net40/Mono.Cecil.dll .
cp /tmp/cecil/lib/net40/Mono.Cecil.dll /tmp/cecil/
git clone --depth=50 git://github.com/csMACnz/monocov.git ../../csMACnz/monocov
cd ../../csMACnz/monocov
cp /tmp/cecil/Mono.Cecil.dll .
./configure
make
sudo make install
# provide these at another location as recommended by http://keithnordstrom.com/getting-the-monocov-profiler-to-link-on-ubuntu-13 and add symbolic links
sudo cp /usr/local/lib/libmono-profiler-monocov.so /usr/lib/
sudo ln -s /usr/lib/libmono-profiler-monocov.so /usr/lib/libmono-profiler-monocov.so.0 
sudo ln -s /usr/lib/libmono-profiler-monocov.so.0 /usr/lib/libmono-profiler-monocov.so.0.0.0
ldd /usr/lib/libmono-profile-monocov.so #DEBUG
popd

xbuild /p:Configuration=Debug clrzmq4.mono.sln

export MONO_TRACE_LISTENER=Console.Out

COVFILE=$(pwd)/ZeroMQ.cov
# ensure /usr/local/lib is in the library path, this is where the monocov instrumentation library is placed
LD_LIBRARY_PATH=/usr/local/lib:${LD_LIBRARY_PATH}
mono --debug --profile=monocov:outfile=${COVFILE},+[ZeroMQ] ./testrunner/NUnit.ConsoleRunner.3.6.1/tools/nunit3-console.exe ./ZeroMQTest/bin/Debug/ZeroMQTest.dll

monocov --export-xml=ZeroMQ.cov.xml ${COVFILE}
REPO_COMMIT_AUTHOR=$(git show -s --pretty=format:"%cn")
REPO_COMMIT_AUTHOR_EMAIL=$(git show -s --pretty=format:"%ce")
REPO_COMMIT_MESSAGE=$(git show -s --pretty=format:"%s")
mono .\\tools\\coveralls.net.0.7.0\\tools\\csmacnz.Coveralls.exe --monocov -i ./ZeroMQ.cov.xml --repoToken $COVERALLS_REPO_TOKEN --commitId $TRAVIS_COMMIT --commitBranch $TRAVIS_BRANCH --commitAuthor "$REPO_COMMIT_AUTHOR" --commitEmail "$REPO_COMMIT_AUTHOR_EMAIL" --commitMessage "$REPO_COMMIT_MESSAGE" --jobId $TRAVIS_JOB_ID  --serviceName travis-ci  --useRelativePaths

revision=${TRAVIS_JOB_ID:=1}
revision=$(printf "%04d" $revision)

#nuget pack ./src/Invio.Extensions.DependencyInjection -c Release -o ./artifacts
