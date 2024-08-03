#!/opt/local/bin/perl5

# Author: Ansgar Endress
# GitHub: https://github.com/aendress/
# Date: 2024
# Version: 0.00001

#################
# LIBRARIES ETC #
#################

use strict;
use warnings;
use File::Basename;
use File::Path qw(make_path);
use Getopt::Long;
use HTTP::Tiny;
use JSON::PP qw(encode_json decode_json);
use Encode qw(encode_utf8);
use YAML::XS;
use MIME::Base64;
use Data::Dumper;
use Encode qw(encode_utf8);

# Turn off output buffering
$| = 1;

##############################
# User customization section #
##############################


# Global debug flag
our $DEBUG_FLAG = 0;  # Set to 1 to enable debug output

my $sensitivity = 0.05;  # Sensitivity for scene detection (0-1). Higher values result in fewer scene changes detected.
my $clip_extra_duration = 0.5;   # Number of seconds to include before and after each scene in the extracted clips.
my $whisper_language = "en";  # Language for Whisper transcription. Use ISO 639-1 codes (e.g., "en" for English, "fr" for French).
my @models = ('llama3.1', 'mistral-nemo');  # List of Ollama models to use for transcription cleaning.
my $use_slides = 0;  # Default to not using slides
my $use_existing_files = 0; 
# Generate an overall lecture summary as well as MCQs for each section
my $make_summary_and_mcqs = 1;
# Print transcriptions with the MCQs for each section? 
my $print_transcriptions_with_mcqs = 1;


# Ollama API configuration
my %ollama_config = (
    base_url => 'http://localhost:11434/api',  # Base URL for Ollama API
    options => {
        temperature => 0.6,  # The temperature of the model. Increasing the temperature will make the model answer more creatively. (Default in ollama: 0.8)
        top_k => 15,         # Reduces the probability of generating nonsense. A higher value (e.g. 100) will give more diverse answers, while a lower value (e.g. 10) will be more conservative. (Default in ollama: 40)
        top_p => 0.35,       # Works together with top-k. A higher value (e.g., 0.95) will lead to more diverse text, while a lower value (e.g., 0.5) will generate more focused and conservative text. (Default in ollama: 0.9) 
        num_ctx => 8192,    # Sets the size of the context window used to generate the next token. (Default in ollama: 2048)
    }
);

# HTTP request options
my %http_request_options = (
    max_retries => 5,  # Maximum number of times to retry a failed HTTP request
    retry_delay => 5,  # Number of seconds to wait between retry attempts
    timeout => 120,    # Timeout in seconds for HTTP requests
);

#################################
# Prompts for various functions #
#################################

my $slide_description_prompt = qq{You are a popular university professor. Your task is to provide a concise yet informative description of a lecture slide or a set of lecture slides. Follow these guidelines:
1. The goal is to create a supplementary resource that is used by another model alongside a lecture transcription to reconstruct the content of the lecture. The descriptions you will generate will not be used on their own. 
2. Your summary should provide a clear description of the slide content without interpreting or expanding upon it. Do not write anything your are not absolutely sure about. 
3. Describe the main topic or theme of the slide(s).
4. Highlight key points, concepts, or data presented.
5. Mention any significant visual elements (charts, graphs, images) and their relevance.
6. Summarize any listed items or bullet points.
7. Describe the overall structure or layout of the information if it's significant to understanding the content.
8. If there are multiple slides, provide a brief overview of how they relate to each other or progress.
9. Keep your description focused and relevant to the educational content.
10. Aim for clarity and objectivity in your description.
11. When some parts are considered humorous, ignore them.
12. Describe the main topic or theme of the slides..
13. Do not create subheadings corresponding to these instructions, but provide a narrative.
14. Do not write any introductory message but just print the description.

Now, please describe the following slide image based on these guidelines:};

my $multimodal_transcription_prompt = qq{You are a popular university professor. You are an expert in creating engaging and educational lecture notes from raw transcriptions and slide descriptions. Transform the given transcription into well-structured, easy-to-read, and captivating lecture notes. You will see descriptions of the corresponding lecture slides as well, but incorporate them only if information from the slide description is clearly relevant to the transcription and if it provides additional detail. Follow these guidelines:
1. Correct any grammatical errors or speech disfluencies in the transcription.
2. Organize the content into a logical structure with clear paragraphs.
3. Highlight key points or main ideas, using engaging language to emphasize their importance.
4. Remove unnecessary repetitions, filler words, or off-topic remarks from the transcription.
5. Maintain the original meaning and key information from the lecture.
6. Rely primarily on the transcription rather than the lecture slide descriptions. Incorporate information from the slide description only if you are certain that it is directly relevant to the transcription and provides additional clarity or information. Otherwise, ignore the slide descriptions. 
7. Do not mention the slides.
8. Keep the tone engaging, conversational, and educational. 
9. Aim for clarity and conciseness without losing important details.
9. If parts of the transcriptions appear to be humorous, ignore those parts in the output.
10. Do not add information that is not in the transcript or slide description.
11. Do not write any introductory message or any other comments on your part. Just output your edited transcription.
12. If you use headings, use them sparingly. Don't use subheadings.
13. Create a title for the output.

Below, you are provided first with a transcription of a lecture part, and then by descriptions of the corresponding slides. Create the lecture notes based on the intructions above.};

my $unimodal_transcription_prompt = qq{You are a popular university professor. You are an expert in creating engaging and educational lecture notes from raw transcriptions. Transform the given transcription into well-structured, easy-to-read, and captivating lecture notes. Follow these guidelines:
1. Correct any grammatical errors or speech disfluencies.
2. Organize the content into a logical structure with clear paragraphs.
3. Highlight key points or main ideas, using engaging language to emphasize their importance.
4. Remove unnecessary repetitions, filler words, or off-topic remarks.
5. Maintain the original meaning and key information from the lecture.
6. Keep the tone engaging, conversational, and educational. 
7. Aim for clarity and conciseness without losing important details.
8. If parts of the transcriptions appear to be humorous, ignore those parts in the output.
9. Do not add information that is not in the transcript.
10. Do not write any introductory message or any other comment on your part. Just output your edited transcription.
11. If you use headings, use them sparingly. Don't use subheadings.
12. Create a title for the output.

Below, you are provided with a transcription of a lecture part. Create the lecture notes based on the intructions above.};

my $overall_summary_system_prompt = qq{You are a popular university professor. Your task is to create a coherent narrative of a lecture based on lecture notes. The input consists of notes for a lecture that are grouped into sections. Follow these guidelines:

1. Create an overall narrative that flows logically from one section to the next.
2. At the beginning, provide a comprehensive overview of the main topics and key points discussed throughout the lecture.
3. Use the section markers as cues to structure your summary, but create a continuous narrative rather than isolated section summaries. Use appropriate transition phrases to connect ideas between sections. Do not refer to sections in the text. 
4. Do not ommit any information present in the input.
5. Do not use language such as "The lecture is about...", "the section shows..." etc. Just state the content, without any such embellishments.
6. Do not mention sections. 
8. Highlight important concepts, theories, or examples presented in each section.
9. Keep the tone professional, informative and engagement. It is addressed at undergraduate students. 
9. Do not add information that is not present in the provided transcriptions.
10. Present all information present in the input, without ommitting detail. Just improve the narrative flow. 
11. Do not include any introductory or concluding remarks about your task; focus solely on the lecture content.
11. Use markdown format. Section heading should start with third level heading.

The lecture summaries start below.};

my $mcq_system_prompt = qq{You are a popular university professor. Your task is to generate multiple-choice questions based on the provided  notes about a part of a lecture. Follow these guidelines:

1. Create 4 multiple-choice questions for the notes.
2. Each question should have 4 options (A, B, C, D).
3. Ensure that the questions cover key concepts and important details from the summary.
4. Vary the difficulty of the questions to assess different levels of understanding.
5. Make sure all options are plausible, but only one is clearly correct.
6. Phrase the questions and options clearly and concisely.
7. Include the correct answer for each question.
8. Format each question as follows:

   Section X, Question Y:
   Question text
   A) Option A
   B) Option B
   C) Option C
   D) Option D
   Correct Answer: [A/B/C/D]

   Where X is the section number and Y is the question number within that section. Include a title for the section.

9. Do not include any introductory or concluding remarks; focus solely on the questions.};

#####################
# General functions #
#####################

# Dependency checks
sub check_dependencies {
    my ($use_slides, $models_ref) = @_;
    my @models = @$models_ref;

    # Check if ffmpeg is installed
    system("which ffmpeg > /dev/null 2>&1") == 0
        or die "Error: ffmpeg is not installed or not in PATH\n";

    # Check if whisper is in the expected location
    my $whisper_path = "/opt/homebrew/bin/whisper";
    die "Error: whisper is not found at $whisper_path\n" unless -x $whisper_path;

    # Check if Ollama is running, start if not
    my $ollama_running = system("pgrep -f 'ollama serve' > /dev/null 2>&1") == 0;
    if (!$ollama_running) {
        print "Ollama is not running. Starting Ollama...\n";
        system("ollama serve > /dev/null 2>&1 &");
        sleep 5;  # Give Ollama some time to start
    }

    # Check if required models are installed
    my $ollama_list = `ollama list`;
    my @installed_models = map { (split /\s+/, $_)[0] } split /\n/, $ollama_list;
    shift @installed_models;  # Remove the header line

    # Check for llava only if slides are being used
    if ($use_slides) {
        my $llava_installed = grep { /^llava(:.*)?$/ } @installed_models;
        die "Error: llava model is not installed.\n" unless $llava_installed;
    }

    # Check user-defined models
    my @missing_models;
    for my $required_model (@models) {
        my $found = grep { /^$required_model(:.*)?$/ } @installed_models;
        push @missing_models, $required_model unless $found;
    }
    
    if (@missing_models) {
        die "Error: The following required Ollama models are not installed: " . join(", ", @missing_models) . "\n";
    }
    
    return $whisper_path;  # Return the whisper path for use in the main script
}

sub trim {
    my $string = shift;
    $string =~ s/^\s+|\s+$//g;
    return $string;
  }


# Function to encode image file to base64
sub encode_image_to_base64 {
    my $file_path = shift;
    open my $image, '<:raw', $file_path or die "Cannot open file $file_path: $!";
    my $image_data = do { local $/; <$image> };
    close $image;
    return MIME::Base64::encode_base64($image_data);
}


# Function to make HTTP requests with retries
sub make_http_request_with_retries {
    my ($url, $payload, $http_request_options) = @_;

	my $is_streaming_request = $payload->{stream} && JSON::PP::is_bool($payload->{stream}) && $payload->{stream} == JSON::PP::true;
    die "This function expect streamed json output" unless $is_streaming_request;

    for my $attempt (1..$http_request_options->{max_retries}) {
        
        my $json_payload = JSON::PP::encode_json($payload);
        
        my $http = HTTP::Tiny->new(timeout => $http_request_options->{timeout});
        my $response = $http->post(
            $url,
            {
                content => $json_payload,
                headers => { 'Content-Type' => 'application/json' }
            }
        );
        
		my $full_content = '';
        if ($response->{success}) {
                
                # Try parsing as streaming response
                my @json_objects = split /\n/, $response->{content};
                
                my $parsed_json;
                foreach my $json_str (@json_objects) {
                    eval {
                        $parsed_json = JSON::PP::decode_json(trim($json_str));
                    };
                    if ($@) {
                        print "DEBUG: JSON parsing failed for object: $json_str\nError: $@\n";
                        next;
                    }
                    
                    if (defined $parsed_json->{message} && 
                        defined $parsed_json->{message}{content}) {
                        $full_content .= $parsed_json->{message}{content};
                    } elsif (defined $parsed_json->{response}) {
                        $full_content .= $parsed_json->{response};
                    }
                }
            
            
            $full_content = trim($full_content);
            return $full_content;
        } else {
            warn "Attempt $attempt failed. HTTP POST error code: ", $response->{status}, "\n",
                 "HTTP POST error message: ", $response->{reason}, "\n";
            
            if ($attempt < $http_request_options->{max_retries}) {
                warn "Retrying in $http_request_options->{retry_delay} seconds...\n";
                sleep $http_request_options->{retry_delay};
            } else {
                die "All $http_request_options->{max_retries} attempts failed. Giving up.\n";
            }
        }
    }
    return "";  # Return empty string if all attempts fail
}

# Function to extract transcriptions and the used models from a yaml file
sub extract_transcriptions_and_models {
    my ($yaml_input_ref) = @_;
    my %models;  # Hash to store models encountered across all documents
    my @transcriptions;  # Array to hold the transcriptions across documents
    my %transcription_concatenations;  # Hash to collect all transcriptions for each model

    foreach my $i (0 .. $#$yaml_input_ref) {
        my $yaml_document = $yaml_input_ref->[$i];

        # Check if the 'cleaned_transcriptions' key exists
        if (exists $yaml_document->{cleaned_transcriptions}) {
            foreach my $model (keys %{$yaml_document->{cleaned_transcriptions}}) {
                $models{$model} = 1;  # Store model name

                # Store each transcription in an array with the model as the key
                push @transcriptions, { $model => $yaml_document->{cleaned_transcriptions}{$model} };

                # Concatenate the transcription data for each model
                $transcription_concatenations{$model} .= "## Section" . ($i + 1) . "\n\n";
                $transcription_concatenations{$model} .= $yaml_document->{cleaned_transcriptions}{$model} . "\n\n";
            }
        } else {
            die "Unexpected YAML structure. Expected 'cleaned_transcriptions' key at the top level.\n";
        }
    }

    return (\%models, \@transcriptions, \%transcription_concatenations);
}

# Read file comprising still images from lecture as well as their time stamps
sub read_time_stamp_file {

	my $timestamp_file = shift;
	
	# Read updated slide_changes.txt and process groups
	# What we are reading in here does not yet have the Group column
	open(my $fh, '<', $timestamp_file) or die "Error: Could not open file '$timestamp_file' $!";
	
	my @groups;
	my @current_group;
	my $group_counter = 0;
	
	# This is the header line
	my $line = 	<$fh>;  
	# The group column exists if the script has been saved on a previous run
	my $group_column_exists = ($line =~ /^\s*Group/) ? 1 : 0;

	while (my $line = <$fh>) {
    	chomp $line;
	    if ($line =~ /^\s*$/) {
    	    push @groups, [@current_group] if @current_group;
        	@current_group = ();
	        $group_counter++;
    	} else {
        	my @fields = split("\t", $line);

	        push @current_group, {
    	        group => $group_column_exists ? $fields[0] : $group_counter + 1,
        	    id => $fields[$group_column_exists + 0],
            	start_pts => $fields[$group_column_exists + 1],
	            start_time => $fields[$group_column_exists + 2],
    	        end_pts => $fields[$group_column_exists + 3],
        	    end_time => $fields[$group_column_exists + 4],
            	slide_file => $fields[$group_column_exists + 5],
	        };
	    }
	}
	push @groups, [@current_group] if @current_group;
	close $fh;
	
	return (@groups);
		
} 	

# Write file comprising still images from lecture as well as their time stamps	
sub write_timestamp_file {
    my ($timestamp_file, $data, $version) = @_;
    
    # Check that the version argument is valid
    die "Error: Invalid version argument. Must be 'original' or 'revised'."
        unless $version eq 'original' or $version eq 'revised';

    open(my $fh, '>', $timestamp_file) or die "Error: Could not open file '$timestamp_file' $!";
    
    if ($version eq 'original') {
        print $fh "ID\tstart_pts\tstart_time\tend_pts\tend_time\tslide_file\ttranscription\n";
        
        for my $timestamp (@$data) {
            print $fh join("\t", 
                $timestamp->{id}, 
                $timestamp->{start_pts}, 
                $timestamp->{start_time}, 
                $timestamp->{end_pts}, 
                $timestamp->{end_time}, 
                $timestamp->{slide_file}, 
                $timestamp->{transcription}
            ), "\n";
        }
    } else {  # $version eq 'revised'
        print $fh "Group\tID\tstart_pts\tstart_time\tend_pts\tend_time\tslide_file\ttranscription\n";
        
        for my $group (@$data) {
            for my $scene (@{$group->{scenes}}) {
                print $fh join("\t",
                    $group->{group},
                    $scene->{id},
                    $scene->{start_pts},
                    $scene->{start_time},
                    $scene->{end_pts},
                    $scene->{end_time},
                    $scene->{slide_file},
                    ""  # Empty transcription column
                ), "\n";
            }
            print $fh "\n";  # Empty line between groups
        }
    }
    
    close $fh;
}


##########################################################################
# Audio and video manipulation, transcription and description functions  #
##########################################################################

sub extract_clip {

    my ($input_file, $output_folder, $output_file, $first_scene, $last_scene, $clip_extra_duration) = @_;

    my $clip_start = $first_scene->{start_time} - $clip_extra_duration;
    $clip_start = 0 if $clip_start < 0;
    my $clip_end = $last_scene->{end_time} ? $last_scene->{end_time} + $clip_extra_duration : '';
    my $duration = $clip_end ? $clip_end - $clip_start : '';

    my $clip_cmd = qq(ffmpeg -i "$input_file" -ss $clip_start);
    $clip_cmd .= $duration ? " -t $duration" : "";
    $clip_cmd .= qq( -c copy "$output_folder/$output_file");

    system($clip_cmd) == 0 or die "Warning: Failed to extract clip $output_file\n";
}


sub transcribe_clip {

	my ($clip_file, $dir, $whisper_language, $whisper_path, $use_existing_files) = @_;

	$clip_file = "$dir/$clip_file";

	my $transcription_file = $clip_file =~ s/\.mp4$/\.txt/r;

    my $transcription; 

	if ($use_existing_files && (-e "$transcription_file")) {
		open (my $fh, '<', "$transcription_file") or
			die "Could not open file $transcription_file: $!";
		
		# Read the entire file content into a scalar
		$transcription = do {
	    local $/; # Enable 'slurp' mode
    	<$fh>;    # Read the whole file
    		};

		# Close the file handle
		close($fh);
	
	} else {    
	    my $whisper_cmd = qq($whisper_path "$clip_file" --output_format txt --language $whisper_language --output_dir $dir);
		$transcription = `$whisper_cmd`;
	}
    
	# Clean up the transcription
    $transcription =~ s/\[.*?\]\s*//g;
    $transcription =~ s/^\s+|\s+$//g;  # Trim leading and trailing whitespace
    $transcription =~ s/\n/ /g;  # Remove all line breaks
    $transcription = trim($transcription);  # Trim whitespace
    
    return ($transcription);
}



# Function to describe slide using llava
sub describe_slide {
    my ($slide_path, $prompt, $ollama_config, $http_request_options) = @_;

    $prompt = trim($prompt);
    
    my $base64_image = encode_image_to_base64($slide_path);
    
    my $payload = {
        model => "llava",
        prompt => $prompt,
        images => [$base64_image],
		stream => JSON::PP::true,
        options => $ollama_config->{options}
    };

    print "Describing slide: $slide_path\n";
    
    my $url = $ollama_config->{base_url} . '/generate';
    my $description = make_http_request_with_retries($url, $payload, $http_request_options);
    
    return $description;
}

##########################################
# Functions for cleaning transcriptions  #
##########################################

# Function to clean transcriptions
sub clean_transcription {
    my ($transcription, $model, $system_prompt, $user_prompt, $ollama_config, $http_request_options) = @_;

    my $payload = {
        model => $model,
        messages => [
            { role => "system", content => $system_prompt },
            { role => "user", content => $user_prompt }
        ],
	stream => JSON::PP::true,
	options => $ollama_config->{options}
    };

	if ($DEBUG_FLAG){
	    print "DEBUG: Cleaning transcription with model: $model\n";
    	print "DEBUG: Transcription length: " . length($transcription) . "\n";
	    print "DEBUG: System prompt length: " . length($system_prompt) . "\n";
    	print "DEBUG: User prompt length: " . length($user_prompt) . "\n";
    }
    
    my $url = $ollama_config->{base_url} . '/chat';
    my $cleaned_transcription = make_http_request_with_retries($url, $payload, $http_request_options);

	if ($DEBUG_FLAG){
    	print "DEBUG: Cleaned transcription length: " . length($cleaned_transcription) . "\n";
        	
    	if (length($cleaned_transcription) > 0) {
        	print "DEBUG: First 100 characters of cleaned transcription: " . substr($cleaned_transcription, 0, 100) . "...\n";
    	} else {
        	print "DEBUG: Cleaned transcription is empty!\n";
    	}
    }
    
    return $cleaned_transcription;
}

#############################################################
# Functions for generating the overall summary and the MCQs #
#############################################################

# Function to generate overall summary using Ollama
sub generate_overall_summary {
    my ($transcription, $model, $ollama_config, $http_request_options, $system_prompt) = @_;

    # Debug: Print received arguments
    if ($DEBUG_FLAG){
	    print "DEBUG: generate_overall_summary received arguments:\n";
	    print "  Model: $model\n";
    	print "  Ollama options: ", Data::Dumper::Dumper($ollama_config);
	    print "  HTTP options: ", Data::Dumper::Dumper($http_request_options);
    	print "  System prompt: $system_prompt\n";
	    print "  Transcription (first 100 chars): ", substr($transcription, 0, 100), "...\n\n";
	}

    my $payload = {
        model => $model,
        messages => [
            { role => "system", content => $system_prompt },
            { role => "user", content => $transcription },
        ],
        stream => JSON::PP::true,
	    options => $ollama_config->{options}
    };

    my $url = $ollama_config->{base_url} . '/chat';
    return make_http_request_with_retries($url, $payload, $http_request_options);
}

# Function to generate MCQs using Ollama
sub generate_mcqs {
    my ($summary, $model, $ollama_config, $http_request_options, $system_prompt) = @_;

    # Debug: Print received arguments
    if ($DEBUG_FLAG){
	    print "DEBUG: generate_mcqs received arguments:\n";
    	print "  Model: $model\n";
	    print "  Ollama options: ", Data::Dumper::Dumper($ollama_config);
	    print "  HTTP options: ", Data::Dumper::Dumper($http_request_options);
	    print "  System prompt: $system_prompt\n";
	    print "  Summary (first 100 chars): ", substr($summary, 0, 100), "...\n\n";
    }

    my $payload = {
        model => $model,
        messages => [
            { role => "system", content => $system_prompt },
            { role => "user", content => $summary },
        ],
        stream => JSON::PP::true,
	    options => $ollama_config->{options}
    };

    my $url = $ollama_config->{base_url} . '/chat';
    return make_http_request_with_retries($url, $payload, $http_request_options);
}


sub generate_section_mcqs {
    my ($transcriptions_ref, $models_ref, $ollama_config_ref, $http_request_options_ref, $mcq_system_prompt) = @_;
    my @section_questions;  # Array to store the MCQs for each section

    foreach my $transcription_data (@$transcriptions_ref) {
        my %section_mcqs;  # Hash to store MCQs for the current section across all models

        foreach my $model (keys %$transcription_data) {
            print "Processing model: $model\n";
            
            my $full_transcription = $transcription_data->{$model};
                
            # Generate MCQs for the transcription data
            my $questions = generate_mcqs($full_transcription, $model, $ollama_config_ref, $http_request_options_ref, $mcq_system_prompt);
            print "Generated questions for model: $model\n";
            
            # Store the generated questions in the section hash
            $section_mcqs{$model} = $questions;
        }

        # Store the section hash in the array
        push @section_questions, \%section_mcqs;
    }

    return \@section_questions;
}

sub collect_section_mcqs {

    my ($section_questions_ref, $transcriptions_ref, $print_transcriptions_with_mcqs) = @_;
    my @output_lines;

    for my $i (0 .. $#$section_questions_ref) {
        my $question_data = $section_questions_ref->[$i];
        push @output_lines, "## Section " . ($i + 1) . "\n\n";
        foreach my $model (keys %$question_data) {
            push @output_lines, "### Questions generated by $model\n\n";
            if ($print_transcriptions_with_mcqs) {
                push @output_lines, $transcriptions_ref->[$i]->{$model} . "\n\n";
            }
            push @output_lines, $question_data->{$model} . "\n\n";
        }
    }

    return @output_lines;
}


sub generate_summaries_and_mcqs_from_yaml_file {
	my ($yaml_file, $ollama_config_ref, $http_request_options_ref, $mcq_system_prompt, $print_transcriptions_with_mcqs) = @_;

    # Read YAML file
    my @yaml_input;
    eval {
        @yaml_input = YAML::XS::LoadFile($yaml_file);
    };
    if ($@) {
        die "Error reading YAML file $yaml_file: $@\n";
    }

    # Debug: Print the structure of the YAML data
    print "DEBUG: YAML Data Structure:\n", Data::Dumper::Dumper(@yaml_input), "\n" if ($DEBUG_FLAG);

    # Extract models and transcriptions from YAML data
    my ($models_ref, $transcriptions_ref, $transcription_concatenations_ref) = extract_transcriptions_and_models(\@yaml_input);

	# Debug: Print extracted models and transcriptions
	if ($DEBUG_FLAG){
		print "DEBUG: Extracted Models:\n", Data::Dumper::Dumper($models_ref), "\n";
		print "Extracted Transcriptions:\n", Data::Dumper::Dumper($transcriptions_ref), "\n";
	}


    # Generate overall summaries
    my %overall_summaries;
    foreach my $model (keys %$models_ref) {    
        print "Generating summary for model $model.\n\n";
        $overall_summaries{$model} = generate_overall_summary($transcription_concatenations_ref->{$model}, $model, \%ollama_config, \%http_request_options, $overall_summary_system_prompt);
    }

    # Generate MCQs for each section
	my $section_mcqs_ref = generate_section_mcqs($transcriptions_ref, $models_ref, $ollama_config_ref, $http_request_options_ref, $mcq_system_prompt);

	# Debug: Print section summaries and questions
	if ($DEBUG_FLAG){
		print "DEBUG: Section Questions:\n", Data::Dumper::Dumper($section_mcqs_ref), "\n";
	}


    # Write output to markdown file
    my ($name, $path, $suffix) = File::Basename::fileparse($yaml_file, qr/\.[^.]*$/);
    my $output_file = $path . $name . "_summary.md";

    open(my $fh, ">:encoding(UTF-8)", $output_file) or die "Could not open file '$output_file' $!";

    print $fh "# Lecture Summary\n\n";
    foreach my $model (keys %$models_ref) {    
	
        print $fh "## Summary from model $model\n\n";
        print $fh $overall_summaries{$model} . "\n\n";
    }

    # Print section MCQs
    die "Transcription data and question data have different lengths"
 		unless ($#$transcriptions_ref == $#$section_mcqs_ref);
	
    my @mcq_output_lines = collect_section_mcqs($section_mcqs_ref, $transcriptions_ref, $print_transcriptions_with_mcqs);
    print $fh "# Review Questions\n\n";
    print $fh $_ foreach @mcq_output_lines;

    close $fh;
}


#################
# Help function #
#################

sub print_help {
    print <<EOF;
Lecture Transcriber

Usage: $0 [options] input.mp4

Options:
  --sensitivity=FLOAT   Sensitivity for scene detection (0-1). Default: 0.05
  --extra-duration=FLOAT        Number of seconds to include before and after each scene. Default: 0.5
  --language=STRING     Language for Whisper transcription (ISO 639-1 code). Default: en
  --models=MODEL1,MODEL2,...   Ollama models to use for transcription cleaning. Default: llama3,mistral
  --use-slides          Enable slide description and incorporation into transcription cleaning. Default: disabled
  --temperature=FLOAT   The temperature of the model for cleaning and slide description. Default: 0.6
  --top-k=INT           The top-k value for cleaning and slide description. Default: 15
  --top-p=FLOAT         The top-p value for cleaning and slide description. Default: 0.35
  --num_ctx=INT         Context window used to generate the next token. Set to a sufficient size if you have long system prompts. Default: 8192 (Default in ollama: 2048)
  --max-request-retries=INT  Maximum number of times to retry a failed HTTP request. Default: 5
  --request-retry-delay=INT   Number of seconds to wait between retry attempts. Default: 5
  --request-timeout=INT       Timeout in seconds for HTTP requests. Default: 120
  --base-url=URL        Base URL for Ollama API. Default: http://localhost:11434/api
  --use-existing-files  Use existing files and skip initial processing steps. Default: disabled
  --make-summary-and-mcqs	  Generate an overall lecture summary as well as revision questions for each section. Default: 1
  --debug               Enable debug output
  --help                Display this help message and exit

The script processes lecture videos, extracting slides, transcribing audio, and generating cleaned lecture notes.
For more detailed information, please refer to the documentation.
EOF
    exit;
}

###########################
# Main script starts here #
###########################

my $whisper_path = check_dependencies($use_slides, \@models);

# Parse command line arguments
Getopt::Long::GetOptions(
    "sensitivity=f" => \$sensitivity,
    "extra-duration=f" => \$clip_extra_duration,
    "language=s" => \$whisper_language,
    "models=s" => \@models,
    "use-slides" => \$use_slides,
    "temperature=f" => \$ollama_config{options}{temperature},
    "top-k=i" => \$ollama_config{options}{top_k},
    "top-p=f" => \$ollama_config{options}{top_p},
    "num_ctx=i" => \$ollama_config{options}{num_ctx},			 
    "max-request-retries=i" => \$http_request_options{max_retries},
    "request-retry-delay=i" => \$http_request_options{retry_delay},
    "request-timeout=i" => \$http_request_options{timeout},
    "base-url=s" => \$ollama_config{base_url},
    "use-existing-files" => \$use_existing_files, 
    "make-summary-and-mcqs" => \$make_summary_and_mcqs,
    "debug" => \$DEBUG_FLAG,
    "help" => sub { print_help() }
) or die "Error in command line arguments\n";

my $input_file = shift @ARGV or die "Usage: $0 [options] input.mp4\n";
die "Error: Input file does not exist\n" unless -e $input_file;
die "Error: Input file is not an MP4 file\n" unless $input_file =~ /\.mp4$/i;

# Create temporary folder
my ($name, $path, $suffix) = File::Basename::fileparse($input_file, qr/\.[^.]*$/);
my $output_folder = $name;

my @timestamps;
my $timestamp_file = "$output_folder/" . $output_folder . "_slide_changes.txt";
my $fh;

if (!$use_existing_files) {
  if (-e $output_folder) {
    print "Temporary folder '$output_folder' already exists. Overwrite? (y/n): ";
    my $answer = <STDIN>;
    chomp $answer;
    exit unless lc($answer) eq 'y';
  }
  File::Path::make_path($output_folder);
  
  # Extract still images
  my $extract_cmd = qq(ffmpeg -i "$input_file" -vf "select='gt(scene,$sensitivity)',metadata=print" -vsync vfr -q:v 2 "$output_folder/frame_%04d.jpg");
  system($extract_cmd) == 0 or die "Error: Failed to extract still images\n";

  # Run ffmpeg command and process output directly
  open(my $ffmpeg_output, "ffmpeg -i \"$input_file\" -vf \"select='gt(scene,$sensitivity)',showinfo\" -vsync vfr -an -f null - 2>&1 |")
    or die "Error: Failed to run ffmpeg command: $!";

  @timestamps = ();
  while (my $line = <$ffmpeg_output>) {
    if ($line =~ /Parsed_showinfo_1.*n:\s*(\d+)\s+.*pts:\s*(\d+)\s+.*pts_time:\s*([\d\.]+)/) {
      push @timestamps, {
			 id => scalar(@timestamps) + 1,
			 frame => $1,
			 start_pts => $2,
			 start_time => $3,
			 end_pts => '',
			 end_time => '',
			 slide_file => sprintf("frame_%04d.jpg", $1),
			 clip_file => sprintf("clip_%03d.mp4", scalar(@timestamps) + 1),
			 transcription => ''
			};
    }
  }
  close($ffmpeg_output);
  
  die "Error: Failed to generate timestamps\n" unless @timestamps;

  # Add end times to timestamps
  for my $i (0 .. $#timestamps - 1) {
    $timestamps[$i]{end_pts} = $timestamps[$i+1]{start_pts};
    $timestamps[$i]{end_time} = $timestamps[$i+1]{start_time};
  }
  
  # Write initial slide_changes.txt  
  write_timestamp_file($timestamp_file, \@timestamps, 'original');
	  
  # Open timestamp file in default application
  my $open_cmd = $^O eq 'darwin' ? 'open' : 'xdg-open';
  system("$open_cmd $timestamp_file");
  
  print "Please review and edit the slide_changes.txt file. Delete unwanted lines and insert empty lines to group scenes. Press Enter when done.";
  <STDIN>;


} else {

    print "Using existing files in '$output_folder'.\n";    
    
}

# Read updated slide_changes.txt and process groups
# This automatically detects whether a group column is included
my @groups = read_time_stamp_file($timestamp_file);

# Process groups, extract clips, transcribe, and clean transcriptions
my @processed_groups;
for my $group (@groups) {
    print "DEBUG: Processing group " . $group->[0]{id} . " to " . $group->[-1]{id} . "\n" if $DEBUG_FLAG;

    my $first_scene = $group->[0];
    my $last_scene = $group->[-1];
    my $group_clip_file = sprintf("clip_%03d-%03d.mp4", $first_scene->{id}, $last_scene->{id});


	extract_clip ($input_file, $output_folder, $group_clip_file, $first_scene, $last_scene, $clip_extra_duration) if (!$use_existing_files);

    # Transcribe the clip
    my $transcription = transcribe_clip($group_clip_file, $output_folder, $whisper_language, $whisper_path, $use_existing_files);

    
    if ($DEBUG_FLAG){
	    print "DEBUG: Original transcription length: " . length($transcription) . "\n";
    	print "DEBUG: First 100 characters of original transcription: " . substr($transcription, 0, 100) . "...\n";
    }

    my $slide_description = "";
    if ($use_slides) {
        # Describe slides
        for my $scene (@$group) {
            my $desc = describe_slide("$output_folder/" . $scene->{slide_file}, $slide_description_prompt, \%ollama_config, \%http_request_options);
            $slide_description .= trim($desc) . "\n\n";
            print "Generated description for slide: " . $scene->{slide_file} . "\n";
        }
        print "DEBUG: Total slide description length: " . length($slide_description) . "\n" if $DEBUG_FLAG;
    }

    my %cleaned_transcriptions;
    for my $model (@models) {
        # Clean transcriptions
        my $system_prompt = $use_slides ? $multimodal_transcription_prompt : $unimodal_transcription_prompt;
        my $user_prompt = $use_slides 
            ? "Transcription:\n$transcription\n\nSlide Description:\n$slide_description"
            : $transcription;
		
		if ($DEBUG_FLAG){
        	print "DEBUG: Cleaning transcription with model: $model\n";
	        print "DEBUG: System prompt length: " . length($system_prompt) . "\n";
    	    print "DEBUG: User prompt length: " . length($user_prompt) . "\n";
    	}
        
        $cleaned_transcriptions{$model} = clean_transcription($transcription, $model, $system_prompt, $user_prompt, \%ollama_config, \%http_request_options);
        
        print "DEBUG: Cleaned transcription length for $model: " . length($cleaned_transcriptions{$model}) . "\n" if $DEBUG_FLAG;
        if (length($cleaned_transcriptions{$model}) > 0) {
            print "DEBUG: First 100 characters of cleaned transcription for $model: " . substr($cleaned_transcriptions{$model}, 0, 100) . "...\n" if $DEBUG_FLAG;
        } else {
            print "DEBUG: Cleaned transcription for $model is empty!\n" if $DEBUG_FLAG;
        }
    }
    
    push @processed_groups, {
        group => $first_scene->{group},
        start_scene => $first_scene->{id},
        end_scene => $last_scene->{id},
        start_time => $first_scene->{start_time},
        end_time => $last_scene->{end_time},
        clip_file => $group_clip_file,
        scenes => $group,
        original_transcription => $transcription,
        slide_description => $slide_description,
        cleaned_transcriptions => \%cleaned_transcriptions,
    };

    print "Processed and transcribed clip $group_clip_file\n";
}

# Write final YAML file
my $yaml_file = "$output_folder/$output_folder" . "_lecture_notes.yaml";
open(my $yaml_fh, '>', $yaml_file) or die "Error: Could not open file '$yaml_file' $!";

my @yaml_output = map {
    {
        group => $_->{group},
        start_scene => $_->{start_scene},
        end_scene => $_->{end_scene},
        start_time => $_->{start_time},
        end_time => $_->{end_time},
        clip_file => $_->{clip_file},
        scenes => [map {
            {
                id => $_->{id},
                start_pts => $_->{start_pts},
                start_time => $_->{start_time},
                end_pts => $_->{end_pts},
                end_time => $_->{end_time},
                slide_file => $_->{slide_file},
            }
        } @{$_->{scenes}}],
        original_transcription => $_->{original_transcription},
        slide_description => $_->{slide_description},
        cleaned_transcriptions => $_->{cleaned_transcriptions},
    }
} @processed_groups;

print $yaml_fh YAML::XS::Dump(@yaml_output);

close $yaml_fh;

# Write final slide_changes.txt
write_timestamp_file($timestamp_file, \@processed_groups, 'revised');

# Delete removed images
my %kept_images = map { $_->{slide_file} => 1 } map { @{$_->{scenes}} } @processed_groups;
opendir(my $dh, $output_folder) or die "Error: Can't open directory '$output_folder': $!";
while (my $file = readdir($dh)) {
    next unless $file =~ /^frame_\d+\.jpg$/;
    unlink("$output_folder/$file") unless $kept_images{$file};
}
closedir($dh);

print "Grouped clips, slide_changes.txt, and lecture_notes.yaml are in the '$output_folder' directory.\n";


exit unless ($make_summary_and_mcqs);

# Make summary and revision questions if necessary

generate_summaries_and_mcqs_from_yaml_file ($yaml_file, \%ollama_config, \%http_request_options, $mcq_system_prompt, $print_transcriptions_with_mcqs);

print "Processing complete.\n";

