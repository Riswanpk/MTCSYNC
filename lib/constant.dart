// Import the functions you need from the SDKs you need
import { initializeApp } from "firebase/app";
import { getAnalytics } from "firebase/analytics";
// TODO: Add SDKs for Firebase products that you want to use
// https://firebase.google.com/docs/web/setup#available-libraries

// Your web app's Firebase configuration
// For Firebase JS SDK v7.20.0 and later, measurementId is optional
const firebaseConfig = {
  apiKey: "AIzaSyAWvRviI_HWf7JnPnYfJbf_FCuiKfutrzk",
  authDomain: "mtc-sync.firebaseapp.com",
  projectId: "mtc-sync",
  storageBucket: "mtc-sync.firebasestorage.app",
  messagingSenderId: "1502033749",
  appId: "1:1502033749:web:7013339cc1efe4c10aa1dc",
  measurementId: "G-LGN5SRFPK3"
};

// Initialize Firebase
const app = initializeApp(firebaseConfig);
const analytics = getAnalytics(app);