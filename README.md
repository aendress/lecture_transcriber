# Lecture Transcriber

## Author

Ansgar Endress
- GitHub: [@adendress](https://github.com/aendress)
- Website: [www.endress.org](https://www.endress.org)

## Version

0.0001

This project is pretty much experimental, as is the documentation. At some point, there will hopefully be a less clunky version.

## What the Script Does

Lecture Transcriber is a Perl script designed to process lecture recordings that contain both an audio stream and a video stream of lecture slides. It creates structured lecture notes based on the lecture audio (and optionally the lecture slides), using the workflow below:

1. Detect scene changes (i.e., slide changes) using FFmpeg.
2. Extract still images of each detected scene/slide along with their timestamps.
3. Allow the user to review and edit the extracted timestamps, enabling them to:
   - Group slides into logical sections
   - Remove any unwanted or irrelevant slides
4. Based on the user's edits, extract video clips for each group of slides (using FFmpeg).
5. Transcribes the audio for each extracted clip (using Whisper).
6. Optionally describes the content of each slide using a visual language model (using llava via Ollama).
7. Generate cleaned transcriptions using specified large language models, potentially incorporating slide descriptions (using models like GPT-4 via Ollama). The current defaults are llama3.1 and mistral-nemo. 
8. Compiles lecture notes as well as a variety of other information into a YAML file for further use.
9. Produces an overall lecture summary and generates multiple-choice questions (MCQs) for each section (using language models via Ollama). This last step is not yet particularly useful. 


## Usage

### Basic Usage

```
./lecture_transcriber.pl [options] input.mp4
```

### Options

- `--sensitivity=FLOAT`: Sensitivity for scene detection (0-1). Higher values result in fewer scene changes detected. Default: 0.05
- `--extra-duration=FLOAT`: Number of seconds to include before and after each scene in the extracted clips. Default: 0.5
- `--language=STRING`: Language for Whisper transcription. Use ISO 639-1 codes (e.g., "en" for English, "fr" for French). Default: en
- `--models=MODEL1,MODEL2,...`: List of Ollama models to use for transcription cleaning. Default models are 'llama3.1' and 'mistral-nemo'.
- `--use-slides`: Enable slide description and incorporation into transcription cleaning. By default, this feature is disabled.
- `--temperature=FLOAT`: The temperature of the model for cleaning and slide description. Increasing the temperature will make the model answer more creatively. Default: 0.6 (Default in Ollama: 0.8)
- `--top-k=INT`: Reduces the probability of generating nonsense. A higher value (e.g. 100) will give more diverse answers, while a lower value (e.g. 10) will be more conservative. Default: 15 (Default in Ollama: 40)
- `--top-p=FLOAT`: Works together with top-k. A higher value (e.g., 0.95) will lead to more diverse text, while a lower value (e.g., 0.5) will generate more focused and conservative text. Default: 0.35 (Default in Ollama: 0.9)
- `--num_ctx=INT`: Sets the size of the context window used to generate the next token. Default: 8192 (Default in Ollama: 2048)
- `--max-request-retries=INT`: Maximum number of times to retry a failed HTTP request. Default: 5
- `--request-retry-delay=INT`: Number of seconds to wait between retry attempts. Default: 5
- `--request-timeout=INT`: Timeout in seconds for HTTP requests. Default: 120
- `--base-url=URL`: Base URL for Ollama API. Default: http://localhost:11434/api
- `--use-existing-files`: Use existing files and skip initial processing steps. Default: disabled
- `--make-summary-and-mcqs`: Generate an overall lecture summary as well as revision questions for each section. Default: enabled
- `--debug`: Enable debug output
- `--help`: Display help message and exit

### Example

```
./lecture_transcriber.pl --sensitivity=0.1 --extra-duration=1 --language=en --models=llama3.1,mistral-nemo --use-slides --temperature=0.7 --top-k=20 --top-p=0.4 --num_ctx=8192 --make-summary-and-mcqs lecture_video.mp4
```

This command will process `lecture_video.mp4` with a scene detection sensitivity of 0.1, include 1 second before and after each scene in clips, use English for transcription, use the llama3.1 and mistral-nemo models for cleaning transcriptions, enable slide description and incorporation, use custom cleaning parameters, and generate a summary and MCQs.

### Output Files

The script will create a folder named after the input file (without the .mp4 extension) containing:

- Extracted slide images
- Video clips for each group of slides
- `[folder_name]_slide_changes.txt`: A tab-separated file with information about each slide change
- `[folder_name]_lecture_notes.yaml`: A YAML file containing all processed information, including original and cleaned transcriptions, and optionally slide descriptions.
- `[folder_name]_lecture_notes_summary.md`: A Markdown file containing the overall lecture summary and MCQs for each section.

## Customization

The script includes several customization options at the beginning of the file. These can be modified to adjust the behavior of the script:

- `$sensitivity`: Default sensitivity for scene detection.
- `$clip_extra_duration`: Default number of seconds to include before and after each scene in clips.
- `$whisper_language`: Default language for Whisper transcription.
- `@models`: Default list of Ollama models to use for transcription cleaning.
- `$use_slides`: Whether to use slide descriptions by default.
- `$use_existing_files`: Whether to use existing files and skip initial processing steps by default.
- `$make_summary_and_mcqs`: Whether to generate an overall lecture summary and MCQs by default.
- `$print_transcriptions_with_mcqs`: Whether to print transcriptions with the MCQs for each section by default.

Additionally, there are several prompts that can be customized:

- `$slide_description_prompt`: Used for describing slides with llava (when --use-slides is enabled).
- `$multimodal_transcription_prompt`: Used for cleaning transcriptions with slide information (when --use-slides is enabled).
- `$unimodal_transcription_prompt`: Used for cleaning transcriptions without slide information.
- `$overall_summary_system_prompt`: Used for generating the overall lecture summary.
- `$mcq_system_prompt`: Used for generating multiple-choice questions.

To customize these, open the script in a text editor and modify the values in the "User customization section" at the beginning of the file.

## Note

Make sure Ollama is running before executing the script. If it's not running, the script will attempt to start it automatically.

## Installation

### Prerequisites

This script requires a Mac with Homebrew installed. If you don't have Homebrew, install it first:

```
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Installing Dependencies

1. Install FFmpeg:

   ```
   brew install ffmpeg
   ```

   FFmpeg is a powerful multimedia framework capable of decoding, encoding, transcoding, muxing, demuxing, streaming, filtering, and playing various media formats. In this script, it's used for video processing and scene detection.

2. Install Whisper:

   ```
   brew install whisper
   ```

   Whisper is an automatic speech recognition (ASR) system developed by OpenAI. It's used in this script to transcribe the audio from the lecture videos.

3. Install Ollama:

   ```
   brew install ollama
   ```

   Ollama is a tool for running large language models locally. It's used in this script to run models like llava (optional), llama3, and mistral for various text processing tasks.

4. Install Perl and cpanm using Homebrew:

   ```
   brew install perl
   brew install cpanm
   ```

   Perl is the programming language in which the script is written. cpanm is a tool for easily installing Perl modules.

5. Ensure you're using the Homebrew version of Perl:

   - For Intel Macs:

     ```
     echo 'export PATH="/usr/local/opt/perl/bin:$PATH"' >> ~/.zshrc
     source ~/.zshrc
     ```

   - For Apple Silicon Macs:

     ```
     echo 'export PATH="/opt/homebrew/opt/perl/bin:$PATH"' >> ~/.zshrc
     source ~/.zshrc
     ```

   (If you're using bash instead of zsh, replace `.zshrc` with `.bash_profile`)

6. Install required Perl modules using cpanm:

   - For Intel Macs:

     ```
     cpanm File::Basename File::Path Getopt::Long HTTP::Tiny JSON::PP Encode YAML::XS MIME::Base64
     ```

   - For Apple Silicon Macs:

     ```
     arch -arm64 cpanm File::Basename File::Path Getopt::Long HTTP::Tiny JSON::PP Encode YAML::XS MIME::Base64
     ```

   Note: If you encounter permission issues, you may need to use sudo. In that case, the commands would be:

   - For Intel Macs:

     ```
     sudo cpanm File::Basename File::Path Getopt::Long HTTP::Tiny JSON::PP Encode YAML::XS MIME::Base64
     ```

   - For Apple Silicon Macs:

     ```
     sudo arch -arm64 cpanm File::Basename File::Path Getopt::Long HTTP::Tiny JSON::PP Encode YAML::XS MIME::Base64
     ```

### Installing the Script

1. Save the script to a file named `lecture_transcriber.pl`.

2. Make the script executable:

   ```
   chmod +x lecture_transcriber.pl
   ```

### Verifying the Installation

After installation, you can verify that you're using the correct version of Perl by running:

```
which perl
```

This should return a path in your Homebrew directory (e.g., `/usr/local/opt/perl/bin/perl` for Intel Macs or `/opt/homebrew/opt/perl/bin/perl` for Apple Silicon Macs).

