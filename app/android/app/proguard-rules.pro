# Razorpay Checkout (razorpay_flutter) — keep its classes in shrunk release builds.
-keepattributes *Annotation*
-dontwarn com.razorpay.**
-keep class com.razorpay.** {*;}
-optimizations !method/inlining/
-keepclasseswithmembers class * {
  public void onPayment*(...);
}
# Google Pay / UPI intent classes used by Razorpay
-dontwarn com.google.android.apps.nbu.paisa.inapp.client.api.**
-keep class com.google.android.apps.nbu.paisa.inapp.client.api.** {*;}
-keep class proguard.annotation.Keep
-keep class proguard.annotation.KeepClassMembers
