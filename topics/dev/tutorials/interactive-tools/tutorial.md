---
layout: tutorial_hands_on

title: "Galaxy Interactive Tools"
questions:
  - "What is an Interactive Tool on Galaxy (GxIT)?"
  - "How to set up a GxIT?"
objectives:
  - "Discover what Galaxy Interactive Tools (GxIT) are"
  - "Understand how GxITs are structured"
  - "Understand how GxITs work"
  - "Be able to dockerise a basic web application"
  - "Be able to wrap a dockerised application as a GxIT"
  - "Be able to test and debug a new GxIT locally and on a Galaxy server"
  - "Be able to distribute a new GxIT for others to use"
requirements:
  - type: "internal"
    topic_name: dev
    tutorials:
      - tool-integration
      - tool-from-scratch
  - type: "none"
    title: "Docker basics"
time_estimation: '3h'
subtopic: tooldev
key_points:
  - "Galaxy Interactive Tools (GxIT) provide an interface for external web applications to be embedded in Galaxy"
  - "GxITs require complex architecture, but most of this is handled by Galaxy core"
  - "Example GxITs are Jupyter notebooks, RStudio or R Shiny apps"
  - "GxITs are heavily dependant on container technologies like Docker"
  - "If a tool is containerized, it can be integrated rapidly into Galaxy as a GxIT"
  - "In theory, any containerized web application can be wrapped as a GxIT"
contributors:
  - eancelet
  - yvanlebras
  - neoformit
  - Lain-inrae
  - abretaud
  # editing
  - hexylena

---

<!--

Notes:

Recommendations for version numbering?

There are 2 Docker repositories:
https://github.com/abretaud/geoc_gxit_ansible/
hub.docker.com and http://quay.io/

Container dependancies on Galaxy:
https://docs.galaxyproject.org/en/latest/admin/special_topics/mulled_containers.html

The default port of dockerized RShiny app is 3838

The environment_variables would be needed to retrieve data from Galaxy History. In the example, this is therefore not necessary.

-->

This tutorial demonstrates how to build and deploy a Galaxy Interactive Tool (GxIT). GxITs are accessible through the Galaxy tool panel, like any installed Galaxy tool. Our example application is a simple R Shiny app that we call `Tabulator`.

There are three elements to a GxIT - an application script, a Docker container and a Galaxy tool XML file. This tutorial will take you through creating those components, and installing them as a new Interactive Tool into a local Galaxy instance and an existing Galaxy instance.


> ### {% icon comment %} If you plan to use an existing Galaxy instance
> The Galaxy server requires specific configuration in order to run Interactive Tools! Please refer to [this admin tutorial](https://training.galaxyproject.org/training-material/topics/admin/tutorials/interactive-tools/tutorial.html) for setting up a compatible Galaxy instance for development and testing of your GxIT.
> As well as updating the Galaxy server configuration, you will also have to configure the server's DNS provider to allow wildcard DNS records. This allows Galaxy to create unique host names (subdomains) for GxITs to be served over, separating them from the main Galaxy application.
{: .comment}

> ### Agenda
>
> In this tutorial, we will cover:
>
> 1. TOC
> {:toc}
>
{: .agenda}


## How do Interactive Tools work?

Interactive tools are a special breed of Galaxy tool which is relatively
new to the Galaxy ecosystem - they are a work in progress!
GxITs enable the user to run an entire web application through Galaxy, which
opens as a new tab in the browser. This can enable users to explore and manipulate
data in a rich interface, such as Jupyter notebooks and RStudio. To see some
examples of GxITs in action, take a look at
[Galaxy EU "Live"](https://live.usegalaxy.eu/).


Interactive tool development builds on the canonical tool-wrapping process.
Instead of running a command, the tool feeds user input to a Docker container
running the application. Once it's up and running, the GxIT application can
then be accessed through a unique URL generated by the Galaxy server.
The user can then open the application, interact with their Galaxy data and
then terminate the tool. On termination, the Docker container is stopped and
removed, and the job is considered "complete".


## When is an Interactive Tool appropriate?

In a regular Galaxy tool the user passes data to the tool and waits for it to
run. They then get some output file(s) when the tool run is complete. In an
Interactive Tool, however, the users are provided with a graphical web interface
allowing them to interact with their data in real time. This is great for
visualising data, but if it is possible to provide the same
functionality with a regular tool (e.g. by rendering an HTML file as an output)
then an Interactive Tool might not be necessary.

If you are sure that a static
output is not sufficient, then it's time to start building your first
Interactive Tool!

> ### {% icon comment %} Interactive tool infrastructure
> Interactive tools require some rather complex infrastructure in order to work! However, most of the infrastructure requirements are taken care of by Galaxy core. As such, wrapping a new GxIT requires only three components:
> - Application script(s)
> - Docker container image
> - Galaxy tool XML
>
> However, as we will see in the next section, testing and deploying a GxIT is not so simple.
{: .comment}


# The development process

Since the infrastructure for building GxITs is not as well developed as regular
tool wrapping, the development process is unfortunately not so streamlined.
Where Planemo is typically used for tool linting and testing, the complex
architecture of GxITs requires a local instance or a development server to be built to manually
test and run the tool.
In addition, they are currently not supported by the Galaxy ToolShed and have to be installed
manually. This means that distributed GxITs can be found in [the Galaxy core codebase](https://github.com/galaxyproject/galaxy/tree/dev/tools/interactive),
and they can be manually enabled by the Galaxy server administrator.

However, the build process itself is not too complex!
We can break it down into just a few steps:

1. Find or create the application you wish to install on Galaxy
2. Find or create a Docker image containing this application
3. Write a Galaxy tool XML to pass IT details to Galaxy and pass user input to the Docker container
4. Add the tool XML to your Galaxy server (local or distant)
5. Try out the tool in the Galaxy interface. Error messages might appear in the Galaxy history.
6. If errors occur, revise the container or tool XML, and try again until the application is working.

The last step is likely where the most time is spent - the process requires
iterative development of the Docker image and tool XML until they work together.
As such, reducing the iteration time is the key to quick development! Throughout
the tutorial, we'll sprinkle in some tips on how to speed up the development
cycle.

> ### {% icon comment %} A note on architecture
> When building a GxIT, it is best to keep as much logic as possible in the tool XML, while keeping the Docker image as generic as possible. Why? Updating the tool XML is simple for Galaxy admins and developers in the future. They can view the tool XML directly on the server and understand how the tool works. The Docker image, meanwhile, is relatively opaque to other developers and administrators. To understand the container they must locate the original Dockerfile, which is not always available. Updating the container is more complex, as we will see later. Additionally, keeping the Docker container generic makes it testable outside of Galaxy.
>
> In short: updating the Docker container is hard, but updating the tool XML is easy!
{: .comment}


# The application

The application that we will wrap in this tutorial is a simple web tool which
allows the user to upload `csv` and `tsv` files, manipulate them and download
them. Our application is based on an R Shiny App hosted with Shiny server.

Note that there is no link between this Interactive Tool and the Galaxy history.
More complex applications might be able to read and write outputs to the user's
history to create a more integrated experience - see the
[Additional components section](#galaxy-history-interaction)
to see an example of how this can be done.

Our example can already be found [online](https://github.com/Lain-inrae/geoc-gxit).
In the following sections, we will study how it was built.


> ### {% icon hands_on %} Hands-on
>
> First, let's clone the repository to take a quick look at it.
>
> ```console
> $ git clone https://github.com/Lain-inrae/geoc-gxit
> $ cd geoc-gxit
>
> $ tree .
> ├── Dockerfile
> ├── interactivetool_tabulator.xml
> ├── gxit
> │   ├── app.R
> │   └── install.R
> ├── Makefile
> └── README.md
> ```
> You'll find a Galaxy tool XML, a Dockerfile and two R scripts that will be injected into the container image.
>
{: .hands_on}

## The R scripts

- `app.R` defines the R Shiny application.
- `install.R` will be used by the docker container to install the R packages needed to run `app.R`.

These are specific to your container; these are required for an R-Shiny container, but won't be for other containers like a Jupyter notebook container.

## The Dockerfile

> ### {% icon tip %} A brief primer on Docker
> Docker allows an entire application context to be containerized. A typical web application consists of an operating system, installed dependancies, web server configuration, database configuration and, of course, the codebase of the software itself. A Docker container can encapsulate all of these components in a single "image", which can be run on any machine with Docker installed.
>
> **Essentials of Docker:**
>
> 1. Write an image recipe as a Dockerfile. This single file selects an OS, installs software, pulls code repositories and copies files from the host machine (your computer).
> 2. Build the image from your recipe:
>
>    `docker build -t <image_name> .`
> 3. View existing images with
>
>    `docker image list`
> 4. Run a container with a specified command:
>
>    `docker run <image_name> <command>`
> 5. View running containers:
>
>    `docker ps`
> 6. Stop a running container:
>
>    `docker stop <container_name>`
> 7. Remove a stopped container:
>
>    `docker container rm <container_name>`
> 8. Remove an image:
>
>    `docker image rm <container_name>`
{: .tip}


Let's check out
[the Dockerfile](https://github.com/Lain-inrae/geoc-gxit/blob/master/Dockerfile)
that we'll use to containerize our application.

This container recipe can be used to build a Docker image which can be pushed to a
container registry in the cloud, ready for consumption by our Galaxy instance:

```dockerfile
# Set image to build upon
FROM rocker/shiny

# set author
MAINTAINER Lain Pavot <lain.pavot@inra.fr>

## we copy the installer and run it before copying the entier project to prevent
## reinstalling everything each time the project has changed

COPY ./gxit/install.R /tmp/

RUN \
        apt-get update                                \
    &&  apt-get install -y --no-install-recommends    \
        fonts-texgyre                                 \
    &&  Rscript /tmp/install.R                        \
    &&  apt-get clean autoclean                       \
    &&  apt-get autoremove --yes                      \
    &&  rm -rf /var/lib/{apt,dpkg,cache,log}/         \
    &&  rm -rf /tmp/*                                 ;


# ------------------------------------------------------------------------------

# These default values can be overridden when we run the container:
#     docker run -p 8080:8080 -e PORT=8080 -e LOG_PATH=/tmp/shiny/gxit.log <container_name>

# We can also bind the container $LOG_PATH to a local directory in order to
# follow the log file from the host machine as the container runs. This command
# will create the log/ directory in our current working directory at runtime -
# inside we will find our Shiny app log file:
#     docker run -p 8888:8888 -e LOG_PATH=/tmp/shiny/gxit.log -v $PWD/log:/tmp/shiny <container_name>

ARG PORT=8888
ARG LOG_PATH=/tmp/gxit/gxit.log

ENV LOG_PATH=$LOG_PATH
ENV PORT=$PORT

# ------------------------------------------------------------------------------

RUN mkdir -p $(dirname "${LOG_PATH}")
EXPOSE $PORT
COPY ./gxit /gxit

# This is the command that will be run when the Docker container is launched.
# In this case it will launch the R Shiny app within the container.
CMD R -e "shiny::runApp('/gxit', host='0.0.0.0', port=${PORT})" 2>&1 > "${LOG_PATH}"
```

This image is already hosted on [Docker Hub](https://hub.docker.com/r/ancelete/first-gxit)
, but anyone can use this Dockerfile to rebuild the image if necessary.
If so, don't forget to create a `gxit` folder containing `app.R` and `install.R`
next to your Dockerfile.

> ### {% icon hands_on %} Hands-on
>
> Let's start working on this Docker container.
>
> 1. Install Docker as described on the [docker website](https://docs.docker.com/engine/install/). Click on your distribution name to get specific information.
>
> 2. Now let's use the recipe to build our Docker image.
>
>    ```sh
>    # Build a container image from our Dockerfile
>    IMAGE_TAG="myimage"
>    LOG_PATH=`pwd`  # Create log output in current directory
>    PORT=8765
>    docker build -t $IMAGE_TAG --build-arg LOG_PATH=$LOG_PATH --build-arg PORT=$PORT .
>    ```
>
>    > ### {% icon tip %} Automating the build
>    > While developing the Docker container you may find yourself tweaking and rebuilding the container image many times.
>    > In the GitHub repository linked above, you'll notice that the author has used a `Makefile` to accelerate the build and deploy process.
>    > This allows the developer to simply run `make docker` and `make push_hub` to build and push the container, or `make` to rebuild the container after making changes during development. Check out the `Makefile` to see what commands can be run using `make` in this repository.
>    >
>    {: .tip}
{: .hands_on}

If you are lucky, you might find an available Docker image for the application you are trying to wrap. However, existing Docker images often require some "tweaking" before they will work as a GxIT. Some example configuration changes are:

1. Expose the correct port. The application, Docker and tool XML ports must be aligned!
2. Log output to an external file - useful for debugging.
3. Make the application callable from tool `<command>` - this sometimes requires a wrapper script to interface the application inside the container (we'll take a look at this later).



## Test the image

Before we go pushing our container to the cloud, we should give it a local test run to ensure that it's working correctly on our development machine. Have a play and see how our little web app works!

> ### {% icon hands_on %} Hands-on
> ```sh
> # Run our application in the container
> docker run -it -p 127.0.0.1:8765:$PORT $IMAGE_TAG
>
> # Or to save time, take advantage of the Makefile
> make it
>
> # Give it a few moments to start up, and the application should be available
> # in your browser at http://127.0.0.1:8765
> ```
{: .hands_on}

## Push the image

If you are happy with the image, we are ready to push it to a container registry
to make it accessible to our Galaxy server.

During development, we suggest making an account on
[Docker Hub](https://hub.docker.com/)
if you don't have one already. This can be used for hosting container images
during development.
[Docker Hub](https://hub.docker.com/)
has great documentation on creating repositories, authenticating with tokens
and pushing images.

> ### {% icon hands_on %} Hands-on
> ```sh
> # Set remote tag for your container. This should include your username and
> # repository name for Docker Hub.
> REMOTE=<DOCKERHUB_USERNAME>/my-first-gxit
>
> # Tag your image
> docker tag $IMAGE_TAG:latest $REMOTE:latest
>
> # Authenticate your DockerHub account
> docker login  # >>> Enter username and token for your account
>
> # Push the image
> docker push $REMOTE:latest
> ```
>
> > ### {% icon tip %} Production container hosting
> > For production deployment, the
> > [Galaxy standard](https://docs.galaxyproject.org/en/latest/admin/special_topics/mulled_containers.html)
> > for container image hosting is
> > [Biocontainers](https://biocontainers.pro).
> > This requires you to
> > [make a pull request](https://biocontainers-edu.readthedocs.io/en/latest/contributing.html)
> > against the Biocontainers GitHub repository, so this should only be done when an
> > image is considered production-ready. You can also push your image to a
> > repository on
> > [hub.docker.com](https://hub.docker.com) or
> > [quay.io](https://quay.io)
> > but please ensure that it links to a public code repository
> > (e.g. GitHub) to enable maintenance of the image by the Galaxy community!
> {: .tip}
{: .hands_on}

You should now have a container in the cloud, ready for action.
Check out your repo on Docker Hub and you should find the container image there.
Awesome!

Now we just need to write a tool XML that will enable Galaxy to pull and run
our new Docker container as a Galaxy tool.

## The tool XML

> ### {% icon hands_on %} Hands-on
>
> Create a Galaxy tool XML file named `interactivetool_tabulator.xml`. The file is similar to a regular tool XML, but calls on our remote Docker image as a dependency. The tags that we are most concerned with are:
> - A `<container>` (under the `<requirements>` tag)
> - A `<port>` which matches our container
> - An `<input>` file
> - The `<command>` section
>
> > ### {% icon comment %} Writing the tool command
> >
> > This step can cause a lot of confusion. Here are a few pointer that you will find critical to understanding the process:
> > - The `<command>` will be templated by Galaxy
> > - The templated command will run *inside* the Docker container
> >
> {: .comment}
>
> > ### {% icon tip %} Writing the GxIT tool XML
> >
> > * Refer to the [Galaxy tool XML docs](https://docs.galaxyproject.org/en/latest/dev/schema.html).
> > * You can take inspiration from [Askomics](https://github.com/galaxyproject/galaxy/blob/dev/tools/interactive/interactivetool_askomics.xml), and other [existing Interactive Tools](https://github.com/galaxyproject/galaxy/blob/dev/tools/interactive).
> > * Check XML syntax with [xmlvalidation.com](https://www.xmlvalidation.com/) or [w3schools XML validator](https://www.w3schools.com/xml/xml_validator.asp), or use a linter in your code editor.
> > * [planemo lint](https://planemo.readthedocs.io/en/latest/commands/lint.html) can also be used for XML linting. But be aware that `planemo test` won't work.
> > * When it comes to testing and debugging your tool XML, it can be easier to update the XML file directly on your Galaxy server between tests.
> {: .tip}
>
> > ### {% icon solution %} Solution
> >
> > {% raw  %}
> >
> > ```xml
> > <tool id="interactive_tool_tabulator" tool_type="interactive" name="Tabulator" version="0.1">
> >     <description>Tuto tool for Gxit</description>
> >
> >     <requirements>
> >         <container type="docker">ancelete/geoc-gxit:latest</container>
> >     </requirements>
> >
> >     <entry_points>
> >         <entry_point name="first gxit" requires_domain="True">
> >             <port>8765</port>
> >
> >             <!--
> >                  Some apps have a non-root entrypoint.
> >                  We can provide the URL with a <url> tag like this:
> >                  <url>/my/entrypoint</url>
> >              -->
> >             <url>/</url>
> >
> >         </entry_point>
> >     </entry_points>
> >
> >     <environment_variables>
> >         <!-- These will be accessible as environment variables inside the Docker container -->
> >     </environment_variables>
> >
> >     <command><![CDATA[
> >
> >         ## The command will be templated by Cheetah within Galaxy, and
> >         ## then run inside the Docker container!
> >
> >         ## This only works because Galaxy's user data directory is mapped
> >         ## onto the Docker container at runtime - enabling access to
> >         ## '$infile' and '$outfile' from inside the container.
> >
> >         R -e "shiny::runApp('/gxit', host='0.0.0.0', port=8765)" 2>&1 > "/var/log/tuto-gxit-01.log"
> >         ## The log file can be found inside the container, for debbuging purposes
> >
> >     ]]>
> >     </command>
> >
> >     <inputs>
> >     </inputs>
> >
> >     <outputs>
> >         <!--
> >             Even if our IT doesn't export to Galaxy history,
> >             adding an output ensures to keep track of the IT
> >             execution in the history
> >         -->
> >
> >         <data name="file_output" format="txt"/>
> >     </outputs>
> >
> >     <tests>
> >         <!-- Tests are difficult with GxITs! -->
> >     </tests>
> >
> >     <help> <![CDATA[
> >
> >         Some help is always of interest ;)
> >
> >     ]]></help>
> >     <citations>
> >        <citation type="bibtex">
> >        @misc{
> >             author       = {Lain Pavot - lain.pavot@inrae.fr },
> >             title        = {{first-gxit -  A tool to visualise tsv/csv files }},
> >             publisher    = {INRAE},
> >             url          = {}
> >         }
> >         </citation>
> >     </citations>
> > </tool>
> > ```
> > {% endraw  %}
> {: .solution}
>
> Don't forget to change the image path (see the `$REMOTE` variable above) and the citation to fit your project settings.
{: .hands_on}

# Testing locally

You would like to check your GxIT integration in Galaxy but don't have a development server or don't want to disturb your sysadmin at this point?
Let's check this integration on your machine. You can use a VM if you prefer not to modify your machine environment.

> ### {% icon comment %} A note on the OS
> This part of the tutorial has been tested on Ubuntu and Debian and there is no guaranteed success for other operating systems.
> If you have another OS on your machine (i.e. Windows or MacOS), you may need to use an Ubuntu virtual machine or perhaps try [Windows subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/install).
{: .comment}

## Docker installation

> ### {% icon hands_on %} Hands-on: Install Docker
> Install Docker as described on the [docker website](https://docs.docker.com/engine/install/). Click on your distribution name to get specific information.
{: .hands_on}

## Galaxy installation

> ### {% icon hands_on %} Hands-on: Install Galaxy
>
> For Ubuntu:
> ```sh
> # Install git to get Galaxy project
> sudo apt-get install git
> # Create a working directory and move to it
> mkdir ~/GxIT && cd ~/GxIT
> # Get the galaxy project. A new directory named "galaxy" will be created.
> # This directory contains the whole project
> git clone https://github.com/galaxyproject/galaxy
> # Checkout the last stable version (v21.09 as the time of writing)
> cd galaxy && git checkout v21.09
> ```
{: .hands_on}


## Galaxy configuration

> ### {% icon hands_on %} Hands-on
>
> ```sh
> cd ~/GxIT/galaxy/config
> # Create custom config files
> cat galaxy.yml.interactivetools > galaxy.yml
> cat job_conf.xml.interactivetools > job_conf.xml
> cat tool_conf.xml.sample > tool_conf.xml
> ```
> In `galaxy.yml`, add the `galaxy_infrastructure_url` parameter to the galaxy section:
> ```yaml
> galaxy:
>   galaxy_infrastructure_url: http://localhost:8080
> ```
> This will make galaxy to provide your GxIT using links like <http://your_gxit_identifier.localhost:8080>.
>
> Configure the tool panel by adding a section in `~/GxIT/galaxy/config/tool_conf.xml`:
> ```xml
>   <section id="interactivetools" name="Interactive tools">
>     <tool file="interactive/interactivetool_tabulator.xml" />
>   </section>
> ```
> With these lines, Galaxy will create a new section named "Interactive tools" in the tool panel
> with our interactive tabulator inside.
> Choose whatever name and id you want as long as the id is unique.
> And of course, you have no obligation to put your GxITs in this section.
> You can put them in any section.
>
> Finally, copy your GxIT wrapper to the Interactive Tool directory:
> ```sh
> cp ~/my_filepath/interactivetool_tabulator.xml ~/GxIT/galaxy/tools/interactive/
> ```
{: .hands_on}

## Run Galaxy

Go to the Galaxy directory and:
```sh
./run.sh
```

Galaxy is available at [http://localhost:8080/](http://localhost:8080/) and you should be able to use your GxIT.
Congrats!

# Installing in Galaxy

We now have all the required components, we can install the tool in our
[configured Galaxy instance](#introduction).
This is as simple as dropping the tool XML in the right location inside
the Galaxy core application directory, and adding the tool to our
`tool_conf_interactive.xml` file.

> ### {% icon hands_on %} Hands-on: Installing
>
> 1. Add the tool XML
>
>    Access your Galaxy instance and take a look at the Galaxy application directory on to see the existing Interactive Tools:
>
>    ```sh
>    # Drop into the Galaxy application directory
>    cd /srv/galaxy/server/
>
>    # Show the existing GxIT tool files
>    ls -l tools/interactive
>    ```
>
> 2. Now we can simply create our tools XML here by writing it with `nano`
>
>    ```sh
>    # Open a new file for editing
>    sudo nano tools/interactive/interactivetool_tabulator.xml
>
>    # >>>  paste the XML content from your code editor and save the file
>    ```
>
> 3. Enable the new tool
>
>    This step is the same as activating any other existing Interactive Tool. See [the admin tutorial](https://training.galaxyproject.org/training-material/topics/admin/tutorials/interactive-tools/tutorial.html) for detailed instructions.
>
>    ```sh
>    # Open the Interactive Tools config file for editing:
>    sudo nano /srv/galaxy/config/tool_conf_interactive.xml
>    ```
>
> 4. This configuration file should have been created when
>    [administering the Galaxy instance to serve Interactive Tools](https://training.galaxyproject.org/training-material/topics/admin/tutorials/interactive-tools/tutorial.html)
>    We just need to add a single line to this file to enable our tool. Can you figure it out?
>
>    > ### {% icon solution %} Solution
>    > ```xml
>    > <toolbox monitor="true">
>    >     <section id="interactivetools" name="Interactive Tools">
>    >         <tool file="interactive/interactivetool_tabulator.xml" />
>    >     </section>
>    > </toolbox>
>    > ```
>    {: .solution}
>
> 5. Now we just need to restart the Galaxy server to refresh the tool registry
>
>    ```sh
>    sudo service galaxy restart
>    ```
>
{: .hands_on}

Have a look in the web interface of your Galaxy instance. You should find the new tool under the "Interactive tools" section in the tool panel. If so, we are ready to start testing it out!

> ### {% icon tip %} Distributing a new GxIT
>
> To release a GxIT for production use, we must distribute two components:
> - the Galaxy tool XML
> - the Docker image
>
> We have already pushed the Docker image to the cloud (thought it should be hosted on an [approved registry](#push-the-image) for production use).
>
> All that's left is to distribute the tool XML. This would conventionally be done through the ToolShed. But the ToolShed doesn't support GxITs yet! This leaves us only two options for distributing the tool XML:
> - Make a pull request against [Galaxy core](https://github.com/galaxyproject/galaxy) to include the XML file under `tools/interactive/`
> - Deploy the tool to specific Galaxy instance(s) in an Ansible Playbook
>
{: .tip}

> ### {% icon tip %} Install a GxIT with an Ansible playbook
>
> The steps that we took in this section can be easily incorporated into an Ansible playbook for deploying GxITs to a Galaxy server. This means that you can manage and deploy a GxIT as part of your Galaxy instance without merging into the `galaxyproject/galaxy` repository (or a fork of it).
>
> The [Interactive Tools admin tutorial](https://training.galaxyproject.org/training-material/topics/admin/tutorials/interactive-tools/tutorial.html)
> demonstrates how this can be acheived by adding our tool XML to the "local tools" section of the Ansible Playbook. However, for our GxIT to show up in the correct tool panel we'll need to add an extra config file: `local_tool_conf.xml`.
>
>
> 1. Copy the GxIT tool XML to `files/galaxy/tools/interactivetool_tabulator.xml` in your Ansible directory
>
> 2. Create the template `templates/galaxy/local_tool_conf.xml.j2`
>
>    {% raw %}
>    ```xml
>    <?xml version='1.0' encoding='utf-8'?>
>    <toolbox monitor="true" tool_path="{{ galaxy_local_tools_dir }}">
>        <section id="interactivetools" name="Interactive tools">
>            <tool file="interactivetool_tabulator.xml" />
>        </section>
>    </toolbox>
>    ```
>    {% endraw %}
>
> 3. Create variables in the following sections of `group_vars/galaxyservers.yml`
>
>    {% raw %}
>    ```yaml
>    # ...
>    galaxy_local_tools_dir: "{{ galaxy_server_dir }}/tools/local"
>    galaxy_tool_config_files:
>      # ...
>      - "{{ galaxy_config_dir }}/local_tool_conf.xml"
>    ```
>    {% endraw %}
>
>
> 4. Run the playbook and your Interactive Tool should be available at the bottom of the tool panel
>
>    ```sh
>    ansible-playbook galaxy.yml
>    ```
>
{: .tip}

# Debugging

The most obvious way to test a tool is simply to run it in the Galaxy UI, straight from the tool panel. If you are extremely lucky, you will find that the tool starts up and runs without error. But we all know that never happens! So this is where we start iteratively debugging our tool, until it functions as expected.

> ### {% icon comment %} A successful tool run
> It is worth pointing out that the appearance of a GxIT in the Galaxy user history is not intuitive when you are used to running "regular" tool jobs. When the history item turns orange ("processing"), that's when a GxIT is actually ready to use! At this point, the tool UI should refresh and display a link to the active GxIT. Remember, the history item doesn't turn green until a job has terminated. With a GxIT, that only happens when the tool has been stopped by the user, or by wall time limits imposed by the Galaxy administrators.
{: .comment}

> ### {% icon tip %} GxIT testing infrastructure
> Testing and debugging is currently the trickiest part of GxIT development. Ideally, Galaxy core will be developed in the future to better support the process, but for the time being we have to make the most with what is available! In the future, we would like to see GxITs being tested with Planemo, and being installed and tested by Ephemeris from the ToolShed.
{: .tip}


# Additional components

The GxIT that we wrapped in this tutorial was a simple example, and you should now understand what is required to create an Interactive Tool for Galaxy. However, there are a few additional components that can enhance the reliability and user experience of the tool. In addition, more complex applications may require some additional components or workarounds the create the desired experience for the user.

## Run script
In the case of our `Tabulator` application, the run script is simply the R script that renders our Shiny App. It is quite straightforward to call this from our Galaxy tool XML. However, some web apps might require more elaborate commands to be run. In this situation there are a number of solutions demonstrated in the `<command>` section of [existing GxITs](https://github.com/galaxyproject/galaxy/tree/dev/tools/interactive):
- [Guacamole Desktop](https://github.com/galaxyproject/galaxy/blob/dev/tools/interactive/interactivetool_guacamole_desktop.xml): application startup with `startup.sh`
- [HiCBrowser](https://github.com/galaxyproject/galaxy/blob/dev/tools/interactive/interactivetool_hicbrowser.xml): application startup with `supervisord`
- [AskOmics](https://github.com/galaxyproject/galaxy/blob/dev/tools/interactive/interactivetool_askomics.xml): configuration with Python and Bash scripts, followed by `start_all.sh` to run the application.

## Templated config files
Using the `<configfiles>` section in the tool XML, we can enable complex user configuration for the application by templating a run script or configuration file to be read by the application. In this application for example, we could use a `<configfiles>` section to template user input into the `app.R` script that runs the application within the Docker container. This could enable the user to customize the layout of the app before launch.

## Reserved environment variables

There are a few environment variables
that are accessible in the command section of the tool XML - these can be handy when writing your tool script.
[check the docs](https://docs.galaxyproject.org/en/latest/dev/schema.html#reserved-variables) for a full reference on the tool XML.

```sh
$__tool_directory__
$__root_dir__
$__user_id__
$__user_email__
```

It can also be useful to create and inject environment variables into the tool context. This can be acheived using the `<environment variables>` tag in the tool XML. The RStudio GxIT again provides an example of this:

```xml
<environment_variables>
    <environment_variable name="HISTORY_ID" strip="True">${__app__.security.encode_id($jupyter_notebook.history_id)}</environment_variable>
    <environment_variable name="REMOTE_HOST">${__app__.config.galaxy_infrastructure_url}</environment_variable>
    <environment_variable name="GALAXY_WEB_PORT">8080</environment_variable>
    <environment_variable name="GALAXY_URL">$__galaxy_url__</environment_variable>
    <environment_variable name="DEBUG">true</environment_variable>
    <environment_variable name="DISABLE_AUTH">true</environment_variable>
    <environment_variable name="API_KEY" inject="api_key" />
</environment_variables>
```

## Galaxy history interaction
We have demonstrated how to pass an input file to the Docker container. But what if the application needs to interact with the user's Galaxy history? For example, if the user creates a file within the application. That's where the environment variables created in the tool XML become useful.

> ### {% icon tip %} Access histories in R
> From the [R-Studio GxIT](https://github.com/galaxyproject/galaxy/blob/dev/tools/interactive/interactivetool_rstudio.xml) we can see that there is [an R library](https://github.com/hexylena/rGalaxyConnector) that allows us to interact with Galaxy histories.
>
> "The convenience functions `gx_put()` and `gx_get()` are available to you to interact with your current Galaxy history. You can save your workspace with `gx_save()`"
>
> Under the hood, this library uses [galaxy_ie_helpers](https://github.com/bgruening/galaxy_ie_helpers) - a Python interface to Galaxy histories written with [BioBlend](https://github.com/galaxyproject/bioblend). You could also use BioBlend directly (or even the Galaxy REST API) if your GxIT requires a more flexible interface than these wrappers provide.
>
{: .tip}

## Self-destruct script

Unlike regular tools, web applications will run indefinitely until terminated. With Galaxy's legacy "Interactive Environments", this used to result in "zombie" containers hanging around and clogging up the Galaxy server. You may notice a `terminate.sh` script in some older GxITs as a workaround to this problem, but the new GxIT architecture handles container termination for you. This script is no longer required or reccommended.


# Troubleshooting

Having issues with your Interactive Tool? Here are a few ideas for how to troubleshoot your application. Remember that Galaxy Interactive Tools are a work in progress, so feel free to get creative with your solutions here!

- Getting an error in the Galaxy History? Click on the "view" icon to see details of the tool run, including the tool command, `stdout` and `stderr`.
- If the tool's `stdout`/`stderr` is not enough, consider modifying the Docker image to make it more verbose. Add print/log statements and assertions. Write an application log to a file that can be collected as Galaxy output.
- Try running the container with Docker directly on your development machine. If the application doesn't work independantly it certainly won't work inside Galaxy!
- If you need to debug the Docker container itself, it can be useful to write output/logging to a [mounted volume](https://docs.docker.com/storage/volumes/) that can be inspected after the tool has run.
- You can also open a `bash` terminal inside the container to check the container state while the application is running: `docker exec -it mycontainer /bin/bash`
