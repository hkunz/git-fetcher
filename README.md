# Git Fetcher (`git-source` / `gsrc`)

`git-source` (or `gsrc` for short) is a command-line tool to fetch archives, latest tags, or branches from Git repositories hosted on **GitHub, GitLab, Bitbucket, or Googlesource**.  It automates the retrieval of the latest version of a repository, saving archives locally.

---

## Features

- Fetch the **latest release tag** or **default branch** automatically.
- Download the repository as a `.tar.gz` archive.
- List all branches of a repository.
- Supports **GitHub**, **GitLab**, **Bitbucket**, and **Googlesource**.
- Optional **verbose** and **debug** output.
- Cross-platform: works anywhere Bash, `curl`, and `git` are available.
- Automatically generate [MXE](https://github.com/mxe/mxe) package (.mk) files from Git repository URLs

---

## Requirements

The following tools must be installed for `git-source` to work properly:

- `bash` – The scripts are written in Bash. Most Linux/macOS systems include this by default.
- `git` – Needed to fetch repository info, list branches, and for `fetch_latest_*` functions.
- `jq` – Required to read/write the JSON database safely. Must be installed separately.
- `curl` or **wget** – Used by `download_archive` to fetch files from URLs.
- `sha256sum` – Used to compute checksums. On macOS, this may be `shasum -a 256`.
- `make` – Needed if building packages locally or running MXE build commands.
- `tar` – Needed to extract source archives.

## Optional Tools

- `MXE toolchain` Only required if you plan to generate `.mk` files and build packages.
- `meson` – Required to detect and configure Meson-based projects.
- `ninja-build` – Needed by Meson as a backend to configure and build projects.
- `cmake` – Required to detect and configure CMake-based projects.
- `patch` – Optional, used if the build scripts apply patches to sources.
- `pkg-config` – Useful for detecting installed libraries when generating `.mk` files.

## Installation

You can run `git-source` directly from the repository without installing:

```bash
# From the project root
./git-source.sh <repo_url_or_owner/repo>

# Install to default prefix (/usr/local)
./install.sh

# Install to a custom prefix, e.g., local user directory
./install.sh --prefix $HOME/.local
```

This installation process will:

* Copy the wrapper `git-source` to `$PREFIX/bin/git-source`
* Create a symlink `gsrc` pointing to the same executable
* Install the man page to `$PREFIX/share/man/man1/git-source.1`
* Record all installed files in `$PREFIX/git-source.install-manifest`

Make sure your `PATH` includes the installation bin directory:

```bash
export PATH="$PREFIX/bin:$PATH"
```

And if you want man pages accessible:

```bash
export MANPATH="$PREFIX/share/man:$MANPATH"
```

## Enable Bash Autocomplete

`git-source` supports `Tab` completion for all flags and options. To enable it:

1. Source the completion script in your current shell:

```bash
source scripts/git-source-completion.sh
```

## MXE Integration (Optional)

The `git-source` command can generate MXE `.mk` files for use in your MXE project using the `--generate-mxe-makefile` or `--generate-mxe-makefile=libname`option. If you want the generated files to be automatically copied into your MXE project, you can set the following environment variables **before running the generator**:

```bash
export MXE_ROOT="/path/to/your/mxe"  # Path to your MXE root directory
export MXE_TARGET="x86_64-w64-mingw32.static"  # Target triplet (optional, defaults to x86_64-w64-mingw32.static)
```

## Uninstallation

To remove installed files, use the `uninstall.sh` script with the same prefix you used for installation:

```bash
# Default prefix
./uninstall.sh

# Custom prefix
./uninstall.sh --prefix $HOME/.local
```

Note: Uninstallation does not affect other system-wide tools or Git repositories you manage. It only removes the installed wrapper, symlink, and `man` page.

## A.I. Automation

### installing the Code Llama AI engine

```bash
$ sudo apt update
$ sudo apt install python3.12-venv
$ python3 -m venv ~/codellama-venv
$ source ~/codellama-venv/bin/activate # run this whenever you start a new terminal session
$ pip install --upgrade pip
$ pip install torch transformers accelerate sentencepiece  # This combined is the AI engine / runtime
```

* `torch` - the neural network engine (PyTorch created by Meta now used by almost everyone)
* `transformers` - loads and runs LLM models (Hugging Face Transformers support thousands of models)
* `accelerate` - helps with GPU/CPU optimization (Hugging Face Accelerate)
* `sentencepiece` - tokenizer used by Llama models created by Google

### install the 7B model weights (~27GB)

```bash
$ mkdir -p ~/models
$ cd ~/models
$ git lfs install
$ git clone https://huggingface.co/codellama/CodeLlama-7b-hf  # These contain the trained neural network weights.
```

### Test A.I.

```python
import sys
import torch
from transformers import AutoTokenizer, AutoModelForCausalLM

model_path = "/home/a/models/CodeLlama-7b-hf"

# -----------------------------------------
# Get prompt from command line argument
# -----------------------------------------
if len(sys.argv) < 2:
    print("Usage: python test_codellama.py \"your prompt here\"")
    sys.exit(1)

prompt = sys.argv[1]

print("Loading tokenizer...")
tokenizer = AutoTokenizer.from_pretrained(model_path)

print("Loading model (this may take a while)...")
model = AutoModelForCausalLM.from_pretrained(
    model_path,
    torch_dtype=torch.float16,
    device_map="auto"
)

print("Model loaded!")

inputs = tokenizer(prompt, return_tensors="pt").to(model.device)

output = model.generate(
    **inputs,
    max_new_tokens=200
)

print("\nAI response:\n")
print(tokenizer.decode(output[0], skip_special_tokens=True))
```

### Sample Usage:

```bash
python test_codellama.py "Hi how are you?"
```