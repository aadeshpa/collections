#!/bin/bash
if [ -n "$TERM" ] && [ "$TERM" != "dumb" ] && [ -x /usr/bin/tput ] && [[ `tput colors` != "0" ]]; then
  color_prompt="yes"
else
  color_prompt=
fi

if [[ "$color_prompt" == "yes" ]]; then
      BLUE="\033[0;34m"
    GREEN="\033[0;32m"
    WHITE="\033[1;37m"
      RED="\033[0;31m"
    YELLOW="\033[0;33m"
  NO_COLOR="\033[0m"
else
        BLUE=""
      GREEN=""
      WHITE=""
        RED=""
  NO_COLOUR=""
fi

note() {
  echo -e "${BLUE}$@${NO_COLOR}"
}
warn() {
  echo -e "${YELLOW}$@${NO_COLOR}"
}
error() {
  echo -e "${RED}$@${NO_COLOR}"
}

run_mvn () {
  echo -e "${GREEN}> mvn $@${NO_COLOR}"
  mvn "$@"
}

common() {
  # Test pom.xml is present and a file.
  if [ ! -f ./pom.xml ]; then
    error "Could not find Maven pom.xml

    * The project directory (containing an .appsody-conf.yaml file) must contain a pom.xml file.
    * On Windows and MacOS, the project directory should also be shared with Docker:
      - Win: https://docs.docker.com/docker-for-windows/#shared-drives
      - Mac: https://docs.docker.com/docker-for-mac/#file-sharing
    "
    exit 1
  fi
  # workaround: exit with error if repository does not exist
  if [ ! -d /mvn/repository ]; then
    error "Could not find local Maven repository

    Create a .m2/repository directory in your home directory. For example:
    * linux:   mkdir -p ~/.m2/repository
    * windows: mkdir %SystemDrive%%HOMEPATH%\.m2\repository
    "
    exit 1
  fi

  # Get parent pom information (appsody-boot2-pom.xml)
  local a_groupId=$(xmlstarlet sel -T -N x="http://maven.apache.org/POM/4.0.0" -t -v "/x:project/x:groupId" /project/appsody-boot2-pom.xml)
  local a_artifactId=$(xmlstarlet sel -T -N x="http://maven.apache.org/POM/4.0.0" -t -v "/x:project/x:artifactId" /project/appsody-boot2-pom.xml)
  local a_version=$(xmlstarlet sel -T -N x="http://maven.apache.org/POM/4.0.0" -t -v "/x:project/x:version" /project/appsody-boot2-pom.xml)
  local a_major=$(echo ${a_version} | cut -d'.' -f1)
  local a_minor=$(echo ${a_version} | cut -d'.' -f2)
  ((next=a_minor+1))
  local a_range="[${a_major}.${a_minor},${a_major}.${next})"

  if ! $(mvn -N dependency:get -q -o -Dartifact=${a_groupId}:${a_artifactId}:${a_version} -Dpackaging=pom >/dev/null)
  then
    # Install parent pom
    note "Installing parent ${a_groupId}:${a_artifactId}:${a_version}"
    run_mvn install -q -f /project/appsody-boot2-pom.xml
  fi

  local p_groupId=$(xmlstarlet sel -T -N x="http://maven.apache.org/POM/4.0.0" -t -v "/x:project/x:parent/x:groupId" pom.xml)
  local p_artifactId=$(xmlstarlet sel -T -N x="http://maven.apache.org/POM/4.0.0" -t -v "/x:project/x:parent/x:artifactId" pom.xml)
  local p_version_range=$(xmlstarlet sel -T -N x="http://maven.apache.org/POM/4.0.0" -t -v "/x:project/x:parent/x:version" pom.xml)

  # Require parent in pom.xml
  if [ "${p_groupId}" != "${a_groupId}" ] || [ "${p_artifactId}" != "${a_artifactId}" ]; then
    error "Project pom.xml is missing the required parent:

    <parent>
      <groupId>${a_groupId}</groupId>
      <artifactId>${a_artifactId}</artifactId>
      <version>${a_range}</version>
      <relativePath/>
    </parent>
    "
    exit 1
  fi

  if ! /project/util/check_version contains "$p_version_range" "$a_version";  then
    error "Version mismatch

The version of the appsody stack '${a_version}' does not match the
parent version specified in pom.xml '${p_version_range}'. Please update
the parent version in pom.xml, and test your changes.

    <parent>
      <groupId>${a_groupId}</groupId>
      <artifactId>${a_artifactId}</artifactId>
      <version>${a_range}</version>
      <relativePath/>
    </parent>
    "
    exit 1
  fi
}

recompile() {
  note "Compile project in the foreground"
  run_mvn compile
}

package() {
  note "Package project in the foreground"
  run_mvn clean package verify
}

debug() {
  note "Build and debug project in the foreground"
  run_mvn spring-boot:run -Dspring-boot.run.jvmArguments='-Xdebug -Xrunjdwp:transport=dt_socket,server=y,suspend=y,address=5005'
}

run() {
  note "Build and run project in the foreground"
  run_mvn clean -Dmaven.test.skip=true spring-boot:run
}

test() {
  note "Test project in the foreground"
  run_mvn package test
}

#set the action, default to fail text if none passed.
ACTION=
if [ $# -ge 1 ]; then
  ACTION=$1
  shift
fi

case "${ACTION}" in
  recompile)
    recompile
  ;;
  package)
    common
    package
  ;;
  debug)
    common
    debug
  ;;
  run)
    common
    run
  ;;
  test)
    common
    test
  ;;
  *)
    error "Unexpected script usage, expected one of recompile, package, debug, run, test"
  ;;
esac
