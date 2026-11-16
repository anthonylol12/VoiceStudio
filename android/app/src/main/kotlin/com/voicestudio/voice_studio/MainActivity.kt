package com.voicestudio.voice_studio

import com.ryanheise.audioservice.AudioServiceActivity

// AudioServiceActivity shares the Flutter engine with the background media
// service, so reading continues with the screen off.
class MainActivity : AudioServiceActivity()
