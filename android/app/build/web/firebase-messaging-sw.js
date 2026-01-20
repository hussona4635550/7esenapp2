importScripts("https://www.gstatic.com/firebasejs/9.23.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/9.23.0/firebase-messaging-compat.js");

firebase.initializeApp({
  apiKey: "AIzaSyDwH7wGp-8_8vw_GlWcvCiJRbBWKWobqM4",
  appId: "1:415589112214:web:9e46f64bc53ef4e4da65b7",
  messagingSenderId: "415589112214",
  projectId: "hesen-notification",
  authDomain: "hesen-notification.firebaseapp.com",
  storageBucket: "hesen-notification.appspot.com",
  measurementId: "G-K3M054KY45"
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage(function (payload) {
  console.log('Received background message ', payload);
}); 