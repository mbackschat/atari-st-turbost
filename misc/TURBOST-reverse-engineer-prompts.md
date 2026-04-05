Your job is to reverse-engineering a Atari ST Game (Turbo ST) with the full source in the src folder. It's rare and there is not much documentation.

Source files are at src/:
- S files : 68000 Assembler
 
## Goals

New files: MANUAL.md, ANALYSIS.md
Updated: Source files (.S)

1. First add comments to the assembler source, to help me better understand it.
This might also help you to gather knowledge.
Specifically, add comments to the code lines and blocks in src/ source files. The goal is that I understand what a sections/routine is doing (adding multi-line comments), but also add comments to instruction blocks (like loops) and even single assembler instructions if the code is non-trivial. I want to read the assembler source and really understand what is going on. Note that I need you to explain Assembler/68000 machine code tricks,  TOS knowhow (trap calls and parameter usage), and algorithms and logic of the Game itself. Try also to reconstruct the signature (parameters and results, and its types) of routines and then add comments to the call sites about it and its parameters.
You might want to read the source files and the ANALYSIS.md for     
better context. And understand that TURBOST.S is a huge source file, so it commenting it might need to happen in (many) batches (with each batch working on a logical unit of this source file).

2. The main goal is to create a comprehensive manual for the Game under MANUAL.md, so that I know how to use the the game source. It needs to document the various modes (editor, game, features and functions etc).
Most of this information must be derived by understanding the 68000 assembler sources in src/ and the TOS calls.

3. Write all your findings to a ANALYSIS.md

So you need to make a plan and consult the provided material (see below).


## Here are some hints:

- The full Atari ST SDK is under atari-tos-main folder:
	- the atari-tos-main/doc/ folder: a comprehensive set of documents about the Atari ST (the actual Developer SDK for Atari ST TOS). So make sure to inspect them and make really make sure to USE this material.
Most relevant is under atari-tos-main/doc is:
	- additional_material/ subfolder
		- TOS.TXT explains the as68 assembler (its options, flags, Directives) and the link68 tools
		- 68000_Assembly_Language.txt explains the 68000 assembler language
	- SDK_DOCS_INDEX.md as a bill-of-material of the docs folder
- Additional: doc/GEM/AES/README.md : about the GEM subsystem of TOS (maybe not really required)

- Also note that I have added atari.s in                                     
  atari-tos-main/doc/additional_material with a list of hardware locations and their symbolic uses.  Check it to add more precise symbols to the
  commented sources, the ANALYSIS.md , and possibly correct statements.

- Note that .doc files are actually ASCII files (with Atari ST specific encoding )!!! There was not Word format back then, so always try unknown extensions as such Atari ST specific ASCII files.
	- Note that some docs are also in PDF format, but prefer .doc, .txt, .md



## Guardrails:

- For the analysis, you can use uv to install local Python libraries. The MUST not be installed globally!!!

- Stay in this project folder, do not go to parent folders!



---






By inspecting the relevant source codes in src/ (which now have extensive comments!!):
Check if ANALYSIS.md is missing something. Maybe surprise findings?
Check if MANUAL.md is missing something.

Again, note that I have added atari.s in                                     
  atari-tos-main/doc/additional_material with a list of hardware locations and their symbolic uses.  Check it to add more precise symbols to the
  commented sources, the ANALYSIS.md , and possibly correct statements.


Then:
In ANALYSIS.md: Add Pseudo-Codes for relevant sections and main logic (by inspecting the relevant source code in src/)
And also propose other parts of the source code where a Pseudo-Code version would help.
Understand that TURBOST.S is a huge source file, be careful to make this detection of potential Pseudo-code candidates efficient.










### Cleanup



Are there any topics in ANALYSIS.md left where Pseudo-Code of the implementation might help understanding? Suggest only. 

❯ OK, go ahead. And write also some motivations and explanations (and maybe findings) around the pseude code blocks (old and new).     

❯ Add pseudocode for the candidates mentioned in "19. Remaining Pseudocode Candidates", and incorporate where into appropriate sections

In ANALYSIS.md: Cross the Pseudo-Code sections with TURBOST.S and if it helps: use the material atari-tos-main/doc/additional_material (about Atari ST TOS and 68000 assembler) as deeper understandings.
Also: remove redundancies, clean up, correct and organize sections best suited for reading. 



In the source TURBOST.s: check how the scenery selection (Rising Sun/City, High Noon/City, Alps/Village) works, which resources      
(images etc) are required and how they are loaded. Is this covered in detail in doc/ANALYSIS.md?           


doc/ANALYSIS.md:   organize sections best suited for reading. And check if some of the pseudocode of section "18. Pseudocode for Key Algorithms" can be moved to earlier sections, e.g. the 18.1 Main Game Loop might be interesting at or after section 3.



Add a final section to ANALYSIS.md about potential improvements.
I am mostly interested in improvements to mechanics, e.g. the curve algorithms etc. Not new features, but maybe better algorithms



### Readme

Create a README.md for this project by consulting doc/MANUAL.md

This is a reverse-engineering of a Car racing Game for the Atari ST

Also check out the folders:
- src/ is the Source code of the Game
- resources/  images and tracks other resources that the game loads
- doc/ markdown files are results of a  reverse-engineering using the sources and the Atari ST material
	- Most relevant is MANUAL.md
	- For technical studies: ANALYSIS.md

(- misc/ leftover from reverse-engineering process, can be ignored!)

show image TITLE.PNG in misc/converted_images as cover image

Create MIT license

For .files in src/ and in resources/, and also misc/TURBOST-Original.S:  Keep the CRLF (do not convert them!)




