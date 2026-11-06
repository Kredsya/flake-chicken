package dev.flakechicken.flake_chicken

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/** Hosts the official MOIS popup. App authentication credentials stay out of this WebView. */
class AddressSearchActivity : Activity() {
    private lateinit var web: WebView
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val launch = intent.getStringExtra("url") ?: run { finish(); return }
        val origin = Uri.parse(BuildConfig.API_ORIGIN)
        val initial = Uri.parse(launch)
        if (!sameOrigin(initial, origin) || !initial.path.orEmpty().startsWith("/address-popup/")) { finish(); return }
        val root = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; fitsSystemWindows = true; setBackgroundColor(Color.WHITE) }
        val back = Button(this).apply { text = "주소 검색 닫기"; setOnClickListener { finish() } }
        val progress = ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal).apply { max = 100 }
        val error = TextView(this).apply { visibility = View.GONE; text = "주소 검색창을 불러오지 못했어요. 닫고 다시 시도해주세요."; setPadding(24, 24, 24, 24) }
        web = WebView(this)
        web.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW
            useWideViewPort = true
            loadWithOverviewMode = true
            builtInZoomControls = true
            displayZoomControls = false
        }
        web.webChromeClient = object : WebChromeClient() {
            override fun onProgressChanged(view: WebView, value: Int) { progress.progress = value; progress.visibility = if (value == 100) View.GONE else View.VISIBLE }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                val uri = request.url
                val juso = uri.scheme == "https" && (uri.port == -1 || uri.port == 443) && (uri.host == "juso.go.kr" || uri.host.orEmpty().endsWith(".juso.go.kr"))
                return !juso && !sameOrigin(uri, origin) && uri.toString() != "about:blank"
            }
            override fun onPageFinished(view: WebView, url: String) {
                val uri = Uri.parse(url)
                if (sameOrigin(uri, origin) && uri.path == initial.path) {
                    view.evaluateJavascript("window.flakeAddressFinished === true") { result ->
                        if (result == "true" && !isFinishing) { setResult(RESULT_OK); finish() }
                    }
                }
            }
            override fun onReceivedError(view: WebView, request: WebResourceRequest, failure: WebResourceError) {
                if (request.isForMainFrame) { error.visibility = View.VISIBLE; progress.visibility = View.GONE }
            }
        }
        root.addView(back)
        root.addView(progress, LinearLayout.LayoutParams.MATCH_PARENT, 5)
        root.addView(error)
        root.addView(web, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f))
        setContentView(root)
        web.loadUrl(launch)
    }
    private fun sameOrigin(uri: Uri, origin: Uri): Boolean = uri.scheme == origin.scheme && uri.host == origin.host && uri.port == origin.port
    override fun onDestroy() { if (::web.isInitialized) { web.stopLoading(); web.destroy() }; super.onDestroy() }
}
