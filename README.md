# NGS Archive Linker
## Overview
The NGS Archive Linker is a Perl script used to generate a structure of links for files stored in the NGS archive.  You are able to get links to the files in an entire project, or to specific samples within a project.

## Install Options


### 1. Install with bioconda

```shell
conda install irida-linker
```

### 2. Install using install.pl script provided
* The script will install a number of Perl modules to the lib/ directory, and install a configuration file in your home directory.
* *Note*: The install script requires cpanm for Perl module installation.

```shell
install/install.pl
```

## Link Structure
Projects and samples in the NGS Archive are stored with the assumption that a sample resides within a project.  To represent this structure on the filesystem, links are generated in the following fashion:

	[output_directory]/[project_name]/[sample_name]/[file_link.fastq]

Example: A project (Project 5) containing multiple samples (Sample 1, Sample 2,Sample 3) and 2 files per sample would be represented as follows:

	output/
		Project 5/
			Sample 1/
				f1_1.fastq
				f1_2.fastq
			Sample 2/
				f2_1.fastq
				f2_2.fastq
			Sample 3/
				f3_1.fastq
				f3_2.fastq

A user is able to use the same output directory for multiple project links.  The new project directory will be created in the root output directory.

## Configuration

The NGS Archive linker uses a configuration file to store the details for connecting to IRIDA.  Your configuration file should include the URL of your IRIDA REST API (usually ending in `/api`) and OAuth2 client credentials for connecting to the API.  The linker requires a `password` grant client.  Information for setting up a client in IRIDA can be found at <https://phac-nml.github.io/irida-documentation/user/administrator/#managing-system-clients>.

An example config file:
```ini
[apiurls]
BASEURL=http://path/to/irida/api

[credentials]
CLIENTID=yourClientId
CLIENTSECRET=yourClientSecret
```

This config file can be saved at one of the following locations:
1. The same directory as the `ngsArchiveLinker.pl` script,
2. `$HOME`/.irida/ngs-archive-linker.conf,
3. `/etc/irida/ngs-archive-linker.conf`.

## Running NGS Archive Linker

### Arguments

* `-p`, `--projectId [ARG]`: The ID of the project to get data from. (required)

* `-o`, `--output [ARG]`: A directory to output the collection of links. (Default: Current working directory)

* `-c`, `igig [ARG]`: The location of the config file. Not required if --baseURL option is used. (Default $HOME/.irida/ngs-archive-linker.conf, /etc/irida/ngs-archive.conf)

* `-b`, `--baseURL [ARG]`: The base URL for the NGS Archive REST API.  Overrides config file setting.

* `-s`, `--sample [ARG]`: A sample id to get sequence files for.  Not required.  Multiple samples may be listed as -s 1 -s 2 -s 3...

* `-t`, `--type [ARG]`: Type of file to link or download. 
Not required. Available options: "fastq", "assembly". Default "fastq". To get both types, you can enter `--type fastq,assembly`

* `-i`, `--ignore`: Ignore creating links for files that already exist.

* `-r`, `--rename`: Rename existing files with `_<number>` suffix. Useful for top up runs with similar filenames. 
**NOTE**: This option overrides the *--ignore* option.

*  `--flat`  : Create links or files in a flat directory under the project name rather than in sample directories.


* `--username`: The username to use for API requests.  Note: if this option is not entered it will be requested during running of the script.

* `--password`: The password to use for API requests.  Note: if this option is not entered it will be requested during running of the script.

* `--download`: Option to download files from the REST API instead of softlinking.  Note: Files may be quite large.  This option is not recommended if you have access to the sequencing filesystem.

* `-v`, `--verbose`: Print verbose messages.

* `-h`, `--help`: Display a help message.

### Usage Examples

#### Linking all files in a project

To get links for all files within a project, you only need to provide the project ID to NGS Archive linker.  The linker will request the list of samples from the REST API to determine which samples it must retrieve.

Example -- Linking all samples for project *4* to directory *files*:

```bash
ngsArchiveLinker.pl --baseURL http://irida.ca/api --project 4 --output files
```

```text
Enter username: test
Enter password: 
Listing all samples from project 4
Created 18 files for 9 samples in files/4
```
#### Linking selected samples within a project

To get links for particular samples within a project, you must provide the project ID and the sample IDs you would like to get links for.
	
Example -- Linking samples 44, 45, and 46 for project *4* to directory *files*:

```bash
ngsArchiveLinker.pl -b http://irida.ca/api --project 4 --sample 44 --sample 45 --sample 46 --output files
```

```text
Enter username: test
Enter password: 
Reading samples 44,45,46 from project 4
Created 6 files for 3 samples in files/4
```

#### Linking assemblies from a project

To get links for assemblies within a project, you must add the `--type assembly` option.  This will tell the linker that you want assemblies instead of sequence file `.fastq` files
	
Example -- Linking all assemblies from project *4* to directory *files*:

```bash
ngsArchiveLinker.pl -b http://irida.ca/api --project 4 --type assembly --output files
```

```text
Enter username: test
Enter password: 
Listing all samples from project 4
Created 1 files for 1 samples in files/4
```

#### Getting new links for an already existing project

To get links for a project that already exists on the filesystem, you can use the **--ignore** option.  This will skip over files and samples that have already been linked and only create links for the new samples.

Example -- 7 samples already exist.  Retrieve rest of new samples from project 4:

```bash
ngsArchiveLinker.pl -b http://irida.ca/api --project 4 --output files --ignore
```

```text
Enter username: test
Enter password: 
Listing all samples from project 4
Created 4 files for 9 samples in files/4
Skipped 14 files as they already exist
```

#### Downloading files

Downloading files rather than linking can be acheived by using the **--download** option.  Arguments for other usages remain the same.

Example -- Download samples 43 and 51 from project *4* to directory *files*:

```bash
ngsArchiveLinker.pl -b http://irida.ca/api --project 4 --sample 43 --sample 51 --output files --download
```

```text
Enter username: test
Enter password: 
Reading samples 43,51 from project 4
** GET http://irida.ca/api/projects/4/samples/51/sequenceFiles/32 ==> 200 OK (11s)
** GET http://irida.ca/api/projects/4/samples/51/sequenceFiles/37 ==> 200 OK (10s)
** GET http://irida.ca/api/projects/4/samples/43/sequenceFiles/31 ==> 200 OK (11s)
** GET http://irida.ca/api/projects/4/samples/43/sequenceFiles/43 ==> 200 OK (11s)
Created 4 files for 2 samples in files/4
```

Note: Downloading files is not recommended if your computer has access to the NGS Archive filesystem as sequence files can be large.

## Errors

* Error: File files/4/46/f1_1.fastq already exists
  > A file that the linker is trying to create already exists on your local filesystem.  It must be removed to be re-linked.  If you would like to ignore existing files and only link new files, use the **--ignore** option.

* Error: Server returned internal server error.  You may have used an incorrect URL for the API.
  > The server returned a HTTP 500 status message.  This may mean that you mistyped the NGS Archive REST API base URL (-b or --baseURL option).  Check the address and try again.

* Error: This user does not have access to the resource at http://irida.ca/api/...
  > The user you used in the application doesn't have access to the files in the NGS Archive REST API.  Talk to the project manager to see if you can be added to the requested project.

* Error: Requested resource wasn't found at http://irida.ca/api/...
  > The sample or project that you requested does not exist in the NGS Archive REST API.  Check your options for the project id (-p or --project) and sample id (-s or --sample) and try again.

## Configuration file

A configuration file, structured as shown below, can be used to feed URLs (`BASEURL`) and, optionally, `USERNAME` and `PASSWORD` can also be stored in the file, but would be overridden if `--password` or `--username` are supplied.

The default locations for the configuration file are `$HOME/.irida/ngs-archive-linker.conf` and ` /etc/irida/ngs-archive.conf`, but a different path can be supplied via `--config FILE`.

```text
[apiurls]
BASEURL=${BASEURL}


[credentials]
CLIENTID=${UPLOADER}
CLIENTSECRET=${CLIENTSECRET}
USERNAME=${IRIDA_USERNAME}
PASSWORD=${IRIDA_PASSWORD}
```
