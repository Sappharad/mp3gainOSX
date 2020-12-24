mp3gainOSX
==========

MP3Gain Express for Mac OS X<br/>
Based on MP3Gain by Glen Sawyer with AACGain by David Lasker<br/>

Mac OS X Express version by Paul Kratt

<dl>
  <dt>What is MP3Gain?</dt>
  <dd>MP3Gain is a tool to increase or decrease the volume of MP3 files without re-encoding them. This is useful when you have a lot of music at different volumes, you can use this tool to make everything the same volume so that you don't need to adjust the volume on your MP3 player when listening to your music on shuffle.</dd>
  <dt>License information</dt>
  <dd>MP3Gain is LGPL. I guess this port is LGPL then, you should adhere to the terms of that license.</dd>
</dl>

See the website for more details: <br/>
http://projects.sappharad.com/mp3gain/

---
Build Instructions:
* aacgain command line: There is an XCode project in the aacgain folder. It requires a pre-configured build environment to work, so the easiest thing to do would be to build the CMake version via the terminal then the XCode project will be able to build going forward. The configure process generates some files like config.h for libplatform in libmp4v2, so at the bare minimum you could just try building the XCode project and every time you get an error you run ./configure for the project that has missing files. Once you've built the command line version at least once, the files you need will exist and you can just use the XCode project to build a universal binary instead.
* MP3GainExpress: Just open and build the XCode project.