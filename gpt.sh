#!/bin/bash

#bash script to run gpt-4o

#cd to the directory of the script
cd "$(dirname "$0")"

#load from env variable
if [ -f .gitkobemoji.env ]; then
    source .gitkobemoji.env
fi

# load from env variable
API_BASE_URL=${GITKOBEMOJI_API_BASE_URL:-http://localhost:11434/api}
API_MODEL=${GITKOBEMOJI_API_MODEL:-llama3.1}

# check if jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found, please install it"
    exit 1
fi

# Function to display help message
display_help() {
    echo "Usage: $0 [options]"
    echo
    echo "Options:"
    echo "  -h              Display this help message"
    echo "  -d              Pipe diff to stdin"
    echo "  -f DIFF.file    Specify the diff file. Will be used to generate the commit message"
    echo "  -g              Generate the commit message (and emoji)"
    echo "  -a              Assess the diff or file."
    echo "  -r              Give starts the rating of the assessment only"
    echo "  -w              Output the assessment in Markdown format"
    echo "  -m \"MESSAGE\"  Specify the commit message"
    echo "  -e              Will analyze message and add the emoji"
    echo "  -v              Verbose mode"
    echo
    echo "Example:"
    echo "  $0 -e -m \"Implement new feature\""
}

# Parse command line arguments
DIFF_CONTENT=""
DIFF_FILE=""
GENERATE=false
ASSESS=false
RATING=false
MARKDOWN=false
MESSAGE=""
RESULT=""
VERBOSE=false
EMOJI=false

while getopts "hdf:garwm:ev" opt; do
  case $opt in
    h)
      display_help
      exit 0
      ;;
    d)
      DIFF_CONTENT=$(cat)
      ;;
    f)
      DIFF_FILE="$OPTARG"
      ;;
    g)
      GENERATE=true
      ;;
    a)
      ASSESS=true
      ;;
    r)
      RATING=true
      ;;
    w)
      MARKDOWN=true
      ;;
    m)
      MESSAGE="$OPTARG"
      ;;
    e)
      EMOJI=true
      ;;
    v)
      VERBOSE=true
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      display_help
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      display_help
      exit 1
      ;;
  esac
done

# Shift the parsed options out of the argument list
shift $((OPTIND-1))

if [ "$VERBOSE" = true ]; then
  echo -e "DIFF_FILE: $DIFF_FILE"
  echo -e "DIFF_CONTENT: $DIFF_CONTENT"
  echo -e "ASSESS: $ASSESS"
  echo -e "RATING: $RATING"
  echo -e "MARKDOWN: $MARKDOWN"
  echo -e "MESSAGE: $MESSAGE"
  echo -e "EMOJI: $EMOJI"
fi

# Check if both emoji and message are provided
if [ "$GENERATE" = true ] && [ -z "$DIFF_CONTENT" ] && [ -z "$DIFF_FILE" ] && [ -z "$MESSAGE" ]; then
  echo "At least one of the following options is required: -d, -f, -m"
  display_help
  exit 1
fi

# Check if both emoji and message are provided
if [ "$ASSESS" = true ] && [ -z "$DIFF_CONTENT" ] && [ -z "$DIFF_FILE" ]; then
  echo "At least one of the following options is required: -d, -f for assessment"
  display_help
  exit 1
fi

get_diff_content() {
  if [ "$VERBOSE" = true ]; then
    echo -e "get_diff_content"
  fi

  #read diff from file
  if [ ! "$DIFF_CONTENT" ] && [ "$DIFF_FILE" ]; then
    if [ ! -f "$DIFF_FILE" ]; then
      echo "no such file $DIFF_FILE"
      exit 1
    fi
    DIFF_CONTENT=$(cat $DIFF_FILE)
  fi

  # Check the size of DIFF_CONTENT
  if [ ${#DIFF_CONTENT} -gt 100000 ]; then
    echo "Error: The diff is too large. Maximum allowed is 100000 characters. (30000 tokens)"
    exit 1
  fi
}

generate_message() {
  if [ "$VERBOSE" = true ]; then
    echo -e "generate_message"
  fi

  get_diff_content

  # Prepare the data for the API call
  SYSTEM_PROMPT="You are a system that generates git commit messages from diff.
  You will be given a diff and your task is to generate a git commit message.
  You will provide only one commit message for each diff.
  Your answer should contain only single commit message, nothing else.
  Use english language only.
  Use a maximum of 72 characters in the response.
  Do not add any extra newlines or spaces at the beginning or end of the message.
  "

  PREFIX_RX="\"" 

  JSON='{
    "model": $api_model,
    "messages": [
      {"role": "system", "content": $system_prompt},
      {"role": "user", "content": $prompt}
    ]
  }'

  DATA=$(jq -n \
    --arg system_prompt "$SYSTEM_PROMPT" \
    --arg prompt "$DIFF_CONTENT" \
    --arg api_model "$API_MODEL" \
    "$JSON")

  # Make the API call
  RESPONSE=$(curl -s \
                  -X POST "$API_BASE_URL/chat" \
                  -H "Content-Type: application/json" \
                  -d "$DATA")

  # Extract and process the answer
  GPT_MESSAGE=$(echo $RESPONSE | jq -r '.message.content' | tr -d '\n' | sed -e 's/[[:space:]]\+/ /g' -e 's/^ *//' -e 's/ *$//')
  
  if [ -z "$MESSAGE" ]; then
    MESSAGE="${GPT_MESSAGE}"
  else
    MESSAGE="${MESSAGE}
${GPT_MESSAGE}"
  fi
  

RESULT=$(echo "${MESSAGE}" | tr -d '\n' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | tr -s ' ')
}

generate_emoji() {
  if [ "$VERBOSE" = true ]; then
    echo -e "generate_emoji"
  fi

  # Prepare the data for the API call
  SYSTEM_PROMPT="You are a system that generates emoji for incoming messages.
  You will be given a message and your task is to generate an emoji that best represents the message.
  You will provide only one emoji for each message.
  Your answer should contain only single emoji, nothing else.
  If possible, use the emoji that is already in the message.
  If possible, use the emoji from the list below:
  | Emoji | Message |
  |-------|-------------|
  | 🎉 | Begin a project. start new priject. initial commit |
  | 🪲 | Fix a bug. bugfix |
  | 🚑 | Critical bug fix. hotfix. |
  | ✨ | Introduce new features. |
  | 📝 | Add or update documentation. |
  | 🚀 | Deploy stuff. |
  | 💄 | Add or update the UI and style files. |
  | 🎨 | Improve structure. cosmetic changes |
  | 🧹 | Run linter or formatter |
  | ⚡ | Improve performance. |
  | 🗑️ | Deprecate code. Remove code or files.|
  | ✅ | Add, update, or pass tests. unit-tests |
  | 🔒 | Fix security issues. |
  | 🔐 | Add or update secrets. |
  | 🔖 | Release / Version tags. |
  | 🚨 | Fix compiler / linter warnings. |
  | 🚧 | Work in progress. |
  | 💚 | Fix CI Build. |
  | ⬇️ | Downgrade dependencies. |
  | ⬆️ | Upgrade dependencies. |
  | 📌 | Pin dependencies to specific versions. |
  | 👷 | Add or update CI build system. |
  | 📈 | Add or update analytics. |
  | ♻️ | Refactor code. |
  | ➕ | Add a dependency. |
  | ➖ | Remove a dependency. |
  | 🔧 | Add or update configuration files. |
  | 🔨 | Add or update development scripts. |
  | 🌐 | Internationalization and localization. |
  | ✏️ | Fix typos. |
  | ⏪ | Revert changes. |
  | 🔀 | Merge branches. |
  | 📦 | Add or update compiled files or packages. |
  | 👽 | Update code due to external API changes. |
  | 🚚 | Move or rename resources. |
  | 📄 | Add or update license. |
  | 💥 | Introduce breaking changes. |
  | 🍱 | Add or update assets. |
  | ♿ | Add or improve accessibility. |
  | 💡 | Add or update comments in source code. |
  | 🗯 | Add or update text and literals. |
  | 🗃 | Perform database changes. |
  | 👥 | Add or update contributor(s). |
  | 🚸 | Improve user experience. |
  | 🏗 | Make architectural changes. |
  | 📱 | Work on responsive design. |
  | 🤡 | Mock things. |
  | 🙈 | Add or update a .gitignore file. |
  | 📸 | Add or update snapshots. |
  | 🏷️ | Add or update types. |
  | 🚩 | Add or update feature flags. |
  | 🥅 | Catch errors. |
  | 💫 | Add or update animations. |
  | 🛂 | Work on authorization. |
  | 🩹 | Simple fix for a non-critical issue. |
  | 🧐 | Data exploration/inspection. |
  | ⚰️ | Remove dead code. |
  | 🧪 | Add a failing test. |
  | 👔 | Add or update business logic. |
  | 🩺 | Add or update healthcheck. |
  | 🧱 | Infrastructure changes. |
  | 🧑‍💻 | Improve developer experience. |
  "

  PREFIX_RX="\"" 

  JSON='{
    "model": $api_model,
    "messages": [
      {"role": "system", "content": $system_prompt},
      {"role": "user", "content": $prompt}
    ]
  }'

  DATA=$(jq -n \
    --arg system_prompt "$SYSTEM_PROMPT" \
    --arg prompt "$MESSAGE" \
    --arg api_model "$API_MODEL" \
    "$JSON")

  # Make the API call
  RESPONSE=$(curl -s \
                  -X POST "$API_BASE_URL/chat" \
                  -H "Content-Type: application/json" \
                  -d "$DATA")

  # Extract and display the answer
  EMOJI=$(echo $RESPONSE | jq -r '.message.content')

  PREFIX="###"

  # check if GITKOBEMOJI_PREFIX_RX is set
  GITKOBEMOJI_PREFIX_RX=$GITKOBEMOJI_PREFIX_RX
  if [ -z "$GITKOBEMOJI_PREFIX_RX" ]; then
      PREFIX="###"
  else
      PREFIX=$GITKOBEMOJI_PREFIX_RX
  fi

  RESULT=$(echo -e "${MESSAGE}" | sed "1s/^\($PREFIX\)\{0,1\}\(.*\)$/\1$EMOJI \2/")
}

assess_diff() {
  if [ "$VERBOSE" = true ]; then
    echo -e "assess_diff"
  fi

  get_diff_content

  # Prepare the data for the API call
  SYSTEM_PROMPT="You are a system that evaluate code quality and assesses the git diff.
  You will be given a diff and your task is to assess this diff.
  Analyze code changes in the diff and provide a detailed evaluation of the changes.
  You will provide only one assessment for each diff.
  Based on the provided git diff evaluate the code changes on several factors: code cleanliness, structure, readability, complexity, and overall code quality.
  Use english language for the response only.
  Use multiple lines for the response.
  Try to use maximum 250 words in the response.
  Limit each line to a maximum of 72 characters for better readability.
  Add the final rating on the scale from 1 to 10 at the end of the response.
  Use 10 emoji ⭐ and 💩 to indicate the rating.
  For example: ⭐⭐⭐⭐⭐⭐⭐💩💩💩 means 7 out of 10 and ⭐⭐⭐⭐⭐⭐⭐⭐⭐⭐ means 10 out of 10.
  "

  if [ "$RATING" = true ]; then
    RATING_PROMPT="
    Your answer should contain only the rating (10 emoji) and nothing else.
    "
    SYSTEM_PROMPT=$(echo -e "${SYSTEM_PROMPT}""${RATING_PROMPT}")
  elif [ "$MARKDOWN" = true ]; then
    RATING_PROMPT="
    Provide all the answer in Markdown format.
    "
    SYSTEM_PROMPT=$(echo -e "${SYSTEM_PROMPT}""${RATING_PROMPT}")
  else
    RATING_PROMPT="
    Provide the answer in plain text format no additional formatting required. Do not use any Markdown formatting.
    "
    SYSTEM_PROMPT=$(echo -e "${SYSTEM_PROMPT}""${RATING_PROMPT}")
  fi

  JSON='{
    "model": $api_model,
    "messages": [
      {"role": "system", "content": $system_prompt},
      {"role": "user", "content": $prompt}
    ]
  }'

  DATA=$(jq -n \
    --arg system_prompt "$SYSTEM_PROMPT" \
    --arg prompt "$DIFF_CONTENT" \
    --arg api_model "$API_MODEL" \
    "$JSON")

  # Make the API call
  RESPONSE=$(curl -s \
                  -X POST "$API_BASE_URL/chat" \
                  -H "Content-Type: application/json" \
                  -d "$DATA")

  # Extract and display the answer
  GPT_MESSAGE=$(echo $RESPONSE | jq -r '.message.content')
  
  if [ -z "$RESULT" ]; then
    RESULT=$(echo -e "${GPT_MESSAGE}")
  else
    RESULT=$(echo -e "${RESULT}" && echo -e "${GPT_MESSAGE}")
  fi
}


if  [ "$GENERATE" = true ] && ([ "$DIFF_CONTENT" ] || [ "$DIFF_FILE" ]); then
  generate_message
fi

if [ "$EMOJI" = true ]; then
  generate_emoji
fi

if [ "$ASSESS" = true ]; then
  assess_diff
fi

echo -e "${RESULT}"
exit 0
