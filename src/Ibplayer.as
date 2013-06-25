package {

	import flash.display.Sprite;
	import flash.display.StageAlign;
	import flash.display.StageScaleMode;
	import flash.events.*;
	import flash.utils.Timer;
	import flash.utils.setTimeout;
	import flash.external.ExternalInterface;
	import flash.media.SoundTransform;
	import flash.media.Video;
	import flash.net.NetConnection;
	import flash.net.NetStream;
	import flash.system.Security;
	import flash.events.NetStatusEvent;
	import flash.events.SecurityErrorEvent;
	
	public class Ibplayer extends Sprite {
		
		private var debugMode:Boolean;
		private var videoRatio:Number;
		private var timer:Timer;
		
		private var currentVideoInfo:Object; 
		private var currentTime:Number;
		private var currentVolume:Number;
		private var duration:Number; 
		private var paused:Boolean;
		private var muted:Boolean;

		private var events:Array;
		
		// video stream
		private var connection:NetConnection;
		private var stream:NetStream;
		private var video:Video;
		
		// api func들에는 prefix "_" 추가.
		public static const API:Array = [
			"init",
			"duration",
			"currentTime",
			"play",
			"pause",
			"paused", // boolean
			"stop",
			"volume",
			"mute",
			"unmute",
			"muted", // boolean
			"load"
		];
		
		public static const EVENTS:Array = [
			"ready",
			"ended",
			"pause",
			"play",
			"progress",
			"timeupdate",
			"volumechange",
			"ratechange", // playback speedrate
			"seeking",
			"seeked",
			"error"
		];
		
		public function Ibplayer ():void {
			Security.allowDomain("*");
			stage.scaleMode = StageScaleMode.NO_SCALE;
			stage.align = StageAlign.TOP_LEFT;
		
			// 외부에서 호출 할 함수 등록
			for (var i:Number = 0; i < API.length; i++) {
				ExternalInterface.addCallback(API[i], this["_" + API[i]]);
				
			}
			
			// 비디오 생성
			video = new Video();
			video.smoothing = true;
			this.addChild(video);

			// resize event
			stage.addEventListener(Event.RESIZE, resize);
			
			// timeupdate event
			timer = new Timer(250);
			timer.addEventListener("timer", timeupdate);

			events = [];
			connect();
			resize();
			timer.start();
			
			_init();
	   }
	   
		public function _init ():void {
			paused = false;
			muted = false;
		}
		
		public function _duration ():Number {
			return duration || 0;
		}
		
		public function _currentTime (seconds:Number = -1):Number {
			//debug("seekTo: " + seconds + "currentTime: " + currentTime);
			if (!stream) {
				return 0;
			}
			if (seconds == -1 || currentTime == seconds) {
				currentTime = stream.time;
				return currentTime || 0;
			} else {
				if (seconds > duration) {
					currentTime = duration;
				} else if (seconds < 0) {
					currentTime = 0;
				} else {
					currentTime = seconds;
				}
				stream.seek(currentTime);
			}
			return currentTime;
		}
		
		public function _play ():void {
			debug("play");
			stream.resume();
			paused = false;
		}
		
		public function _pause ():void {
			debug("pause");
			stream.pause();
			paused = true;
		}
		
		public function _paused ():Boolean {
			debug("paused: " + paused);
			return paused;
		}
		
		public function _stop ():void {
			debug("stop");
			_pause();
			stream.seek(0);
		}
		
		public function _volume (ratio:Number = -1):Number {
			debug("volume: " + ratio);
			if (ratio == -1 || currentVolume == ratio) {
				return currentVolume;
			} else if (stream) {
				if (ratio > 1) {
					currentVolume = 1;
				} else if (ratio < 0) {
					currentVolume = 0;
				} else {
					currentVolume = ratio;
				}
				if (!muted) {
					stream.soundTransform = new SoundTransform(currentVolume);
				}
			}
			return currentVolume;
		}
		
		public function _mute ():void {
			debug("mute");
			if (stream) {
				stream.soundTransform = new SoundTransform(0);
			}
			muted = true;
		}
		
		public function _unmute ():void {
			debug("unmute");
			if (stream) {
				stream.soundTransform = new SoundTransform(currentVolume);
			}
			muted = false;
		}
		
		public function _muted ():Boolean {
			debug("muted: " + muted);
			return muted;
		}
		
		public function _load (info:Object):void {
			debug("load: " + info.src);
			if (info.src) {
				stream.play(info.src);
				stream.pause();
			}
			currentVideoInfo = info;
		}
		
		public function fireEvent(event:String, data:Object = null):void {
			//debug("fireEvent: " + event);
			if (data) {
				ExternalInterface.call("__ibp_as_fireEvent__", event, data);
			} else {
				ExternalInterface.call("__ibp_as_fireEvent__", event);
			}
		}
		
		public function resize (e:Event = null):void {
			video.width = stage.stageWidth;
			video.height = stage.stageWidth * videoRatio;
			video.y = (stage.stageHeight / 2) - (video.height / 2);
		}
				
		public function debug (msg:String, data:Object = null):void {
			debugMode = true;
			if (!debugMode) {
				return;
			}
			ExternalInterface.call("console.log", msg, data);
		}
				
		private function timeupdate (e:Object):void {
			if (!stream) {
				return;
			}
			var buffer:Number = stream.bytesLoaded,
				delta:Number = stream.bytesTotal - buffer;
			fireEvent("timeupdate", { "time": currentTime, "buffer": buffer } );
			
			debug("buff:" + buffer);
		}
		
		private function connect ():void {
			if (connected()) {
				return;
			}
			connection = new NetConnection();
			connection.connect(null);
			connection.addEventListener(SecurityErrorEvent.SECURITY_ERROR, function (e:SecurityError):void {
				debug("sercurity error: " + e.message);
			});
			connection.addEventListener(NetStatusEvent.NET_STATUS, function (e:NetStatusEvent):void {
				switch (e.info.code) {
				case "NetConnection.Connect.Success":
					debug("네트웍에 연결됨");
					break;

				case "NetConnection.Connect.Failed":
					debug("네트웍 연결에 실패");
					break;

				case "NetConnection.Connect.Closed":
					debug("네트웍 연결 종료");
					break;

				case "NetConnection.Connect.Rejected":
					debug("네트웍 연결이 거절됨");
					break;
				}
			});
		
			// stream connection
			stream = new NetStream(connection);
			video.attachNetStream(stream);
			stream.client = {
				onMetaData: function (meta:Object):void {					
					videoRatio = meta.height / meta.width;
					duration = meta.duration;
					resize();
				}
			}
		}
		
		private function disconnect ():void {
			connection.close();
			stream.close();
		}
		
		private function connected ():Boolean {
			return connection && connection.connected;
		}
	}
}