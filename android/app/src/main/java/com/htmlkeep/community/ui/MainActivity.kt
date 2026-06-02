package com.htmlkeep.community.ui

import android.app.Activity
import android.content.ActivityNotFoundException
import android.app.AlertDialog
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.ColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.graphics.drawable.ColorDrawable
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.provider.MediaStore
import android.text.Editable
import android.text.SpannableString
import android.text.Spanned
import android.text.TextWatcher
import android.text.TextUtils
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.view.Gravity
import android.view.Menu
import android.view.MenuItem
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsetsController
import android.view.inputmethod.InputMethodManager
import android.webkit.JavascriptInterface
import android.webkit.MimeTypeMap
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebStorage
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.BaseAdapter
import android.widget.Button
import android.widget.EditText
import android.widget.FrameLayout
import android.widget.GridLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ListView
import android.widget.PopupMenu
import android.widget.PopupWindow
import android.widget.ProgressBar
import android.widget.ScrollView
import android.widget.TextView
import androidx.core.content.FileProvider
import androidx.recyclerview.widget.ItemTouchHelper
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.htmlkeep.community.R
import com.htmlkeep.community.core.DeletedWebPage
import com.htmlkeep.community.core.ShareExporter
import com.htmlkeep.community.core.WebPage
import com.htmlkeep.community.core.WebPageEntrySource
import com.htmlkeep.community.core.WebPageEntry
import com.htmlkeep.community.core.WebPageLibrary
import com.htmlkeep.community.core.WebPageLibraryException
import com.htmlkeep.community.core.WebPageLoadStatus
import com.htmlkeep.community.core.WebPageProjectFile
import com.htmlkeep.community.core.WebPageRuntimeStorage
import com.htmlkeep.community.core.WebPageSearchIndex
import com.htmlkeep.community.core.WebPageSearchResult
import com.htmlkeep.community.core.ZipTools
import org.json.JSONObject
import java.io.ByteArrayInputStream
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.text.DateFormat
import java.util.Calendar
import java.util.Date

class MainActivity : Activity() {
    private val openFileRequestCode = 1001
    private val projectIconPhotoRequestCode = 1002
    private val projectIconFileRequestCode = 1003
    private lateinit var library: WebPageLibrary
    private lateinit var searchIndex: WebPageSearchIndex
    private var screen: Screen = Screen.Home
    private var projectIconTargetPageID: String? = null
    private var activeSearchOverlay: SearchOverlayController? = null
    private val colors: AppPalette
        get() = AppPalette.forContext(this)

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(AppPreferences.localizedContext(newBase))
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        library = WebPageLibrary(File(filesDir, "HTMLKeep"), libraryStrings())
        searchIndex = WebPageSearchIndex(searchIndexFile())
        handleIncomingIntent(intent)
        if (screen is Screen.Home) showHome()
    }

    override fun setContentView(view: View) {
        applyCurrentLayoutDirection(view)
        super.setContentView(view)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    @Deprecated("Deprecated in Android API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == openFileRequestCode && resultCode == RESULT_OK) {
            data?.data?.let { importAndOpen(it) }
        } else if ((requestCode == projectIconPhotoRequestCode || requestCode == projectIconFileRequestCode) && resultCode == RESULT_OK) {
            data?.data?.let { setProjectIconFromUri(it) }
        }
    }

    @Deprecated("Deprecated in Android API")
    override fun onBackPressed() {
        when (val current = screen) {
            Screen.Home -> super.onBackPressed()
            Screen.RecentlyDeleted -> showHome()
            Screen.Settings -> showHome()
            Screen.SettingsHomeLayout -> showSettings()
            Screen.SettingsLanguage -> showSettings()
            Screen.SettingsAppearance -> showSettings()
            is Screen.Viewer -> {
                current.webView.destroy()
                showHome()
            }
            is Screen.DeletedViewer -> {
                current.webView.destroy()
                showRecentlyDeleted()
            }
            is Screen.NativeFileViewer -> showHome()
            is Screen.DeletedNativeFileViewer -> showRecentlyDeleted()
        }
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null) return
        val uri = when (intent.action) {
            Intent.ACTION_VIEW -> intent.data
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            else -> null
        } as? Uri
        if (uri != null) importAndOpen(uri)
    }

    private fun importAndOpen(uri: Uri) {
        try {
            val source = UriSourceReader.read(contentResolver, uri)
            val result = library.importBytes(source.bytes, source.fileName, source.sourceDescription)
            openImportedProject(result.page, result.entry)
        } catch (_: UriSourceReader.SourceTooLargeException) {
            showError(appString(R.string.import_file_too_large))
        } catch (error: WebPageLibraryException) {
            showError(error.message ?: appString(R.string.unreadable_file))
        } catch (_: Throwable) {
            showError(appString(R.string.unreadable_file))
        }
    }

    private fun openImportedProject(page: WebPage, entry: WebPageEntry) {
        if (page.opensInNativeFileViewer) {
            showNativeFileViewer(page)
        } else {
            showViewer(page, entry)
        }
    }

    private fun openPage(page: WebPage) {
        if (page.opensInNativeFileViewer) {
            showNativeFileViewer(page)
        } else {
            showViewer(page, library.defaultEntry(page))
        }
    }

    private fun showHome() {
        screen = Screen.Home
        configureSystemBars(SurfaceMode.Shell)

        val root = FrameLayout(this).apply {
            background = pageBackground()
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        content.addView(homeToolbar { showSearchOverlay(root) }, LinearLayout.LayoutParams(-1, dp(64)))

        if (library.pages.isEmpty()) {
            content.addView(emptyState(), LinearLayout.LayoutParams(-1, 0, 1f))
        } else if (AppPreferences.selectedHomeDisplayMode(this).rawValue == "grid") {
            content.addView(projectGrid(), LinearLayout.LayoutParams(-1, 0, 1f))
        } else {
            content.addView(projectList(), LinearLayout.LayoutParams(-1, 0, 1f))
        }
        root.addView(content, FrameLayout.LayoutParams(-1, -1))
        root.addView(bottomDock(), FrameLayout.LayoutParams(-1, dp(100), Gravity.BOTTOM))
        setContentView(root)
    }

    private fun showSettings() {
        screen = Screen.Settings
        configureSystemBars(SurfaceMode.Shell)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = pageBackground()
        }
        root.addView(toolbar(appString(R.string.settings_title), showBack = true), LinearLayout.LayoutParams(-1, dp(58)))
        root.addView(settingsContent(), LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }

    private fun showSettingsHomeLayout() {
        screen = Screen.SettingsHomeLayout
        configureSystemBars(SurfaceMode.Shell)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = pageBackground()
        }
        root.addView(toolbar(appString(R.string.settings_home_layout), showBack = true), LinearLayout.LayoutParams(-1, dp(58)))
        root.addView(homeLayoutChooser(), LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }

    private fun showRecentlyDeleted() {
        screen = Screen.RecentlyDeleted
        configureSystemBars(SurfaceMode.Shell)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = pageBackground()
        }
        root.addView(toolbar(appString(R.string.recently_deleted), showBack = true), LinearLayout.LayoutParams(-1, dp(58)))
        if (library.recentlyDeletedPages.isEmpty()) {
            root.addView(recentlyDeletedEmptyState(), LinearLayout.LayoutParams(-1, 0, 1f))
        } else {
            root.addView(recentlyDeletedList(), LinearLayout.LayoutParams(-1, 0, 1f))
        }
        setContentView(root)
    }

    private fun showDeletedViewer(deletedPage: DeletedWebPage, entry: WebPageEntry) {
        val projectFolder = library.recoverableFolderFor(deletedPage)
        val entryFile = File(projectFolder, entry.entryRelativePath)
        if (entry.source != WebPageEntrySource.BUNDLED_ARCHIVE_INDEX && !entryFile.exists()) {
            AlertDialog.Builder(this)
                .setTitle(appString(R.string.missing_file_title))
                .setMessage(appString(R.string.recoverable_file_missing))
                .setPositiveButton(appString(R.string.ok), null)
                .show()
            return
        }

        configureSystemBars(SurfaceMode.Viewer)
        val root = FrameLayout(this).apply {
            setBackgroundColor(colors.pageTop)
        }
        val webView = WebView(this)
        val projectLoader = ProjectWebViewLoader(deletedPage.page, projectFolder)

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.allowFileAccess = false
        webView.settings.allowContentAccess = false
        webView.setBackgroundColor(Color.TRANSPARENT)
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                val activeEntry = entryForProjectUrl(deletedPage.page, url) ?: entry
                updateDeletedViewerEntry(activeEntry)
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url ?: return false
                if (ProjectWebViewLoader.isProjectUrl(deletedPage.page, url)) return false
                return if (url.scheme == "http" || url.scheme == "https") {
                    startActivity(Intent(Intent.ACTION_VIEW, url))
                    true
                } else {
                    false
                }
            }

            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                val url = request?.url ?: return null
                return projectLoader.responseFor(url)
            }
        }
        webView.loadUrl(ProjectWebViewLoader.urlFor(deletedPage.page, entry.entryRelativePath).toString())
        root.addView(webView, FrameLayout.LayoutParams(-1, -1))
        val toolbar = deletedViewerToolbar(deletedPage, entry, webView)
        root.addView(toolbar, FrameLayout.LayoutParams(-1, viewerTopChromeHeight(), Gravity.TOP))
        root.addView(recentlyDeletedActionDock(deletedPage), FrameLayout.LayoutParams(-1, dp(104), Gravity.BOTTOM))
        screen = Screen.DeletedViewer(deletedPage.id, entry.id, webView, toolbar)
        applyViewerToolbarMode(toolbar, webView)
        setContentView(root)
    }

    private fun showNativeFileViewer(page: WebPage) {
        configureSystemBars(SurfaceMode.Shell)
        val projectFolder = library.folderFor(page)
        val files = library.projectFilesFor(page)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = pageBackground()
        }
        root.addView(nativeFileViewerToolbar(page), LinearLayout.LayoutParams(-1, dp(58)))
        root.addView(nativeFileList(projectFolder, files, bottomPadding = dp(18)), LinearLayout.LayoutParams(-1, 0, 1f))
        screen = Screen.NativeFileViewer(page.id)
        setContentView(root)
    }

    private fun showDeletedNativeFileViewer(deletedPage: DeletedWebPage) {
        configureSystemBars(SurfaceMode.Shell)
        val projectFolder = library.recoverableFolderFor(deletedPage)
        val files = library.projectFilesFor(deletedPage)

        val root = FrameLayout(this).apply {
            background = pageBackground()
        }
        val content = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
        }
        content.addView(
            nativeFileViewerToolbar(deletedPage.page, showActions = false),
            LinearLayout.LayoutParams(-1, dp(58))
        )
        content.addView(nativeFileList(projectFolder, files, bottomPadding = dp(116)), LinearLayout.LayoutParams(-1, 0, 1f))
        root.addView(content, FrameLayout.LayoutParams(-1, -1))
        root.addView(recentlyDeletedActionDock(deletedPage), FrameLayout.LayoutParams(-1, dp(104), Gravity.BOTTOM))
        screen = Screen.DeletedNativeFileViewer(deletedPage.id)
        setContentView(root)
    }

    private fun showSettingsLanguage() {
        screen = Screen.SettingsLanguage
        configureSystemBars(SurfaceMode.Shell)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = pageBackground()
        }
        root.addView(toolbar(appString(R.string.settings_language), showBack = true), LinearLayout.LayoutParams(-1, dp(58)))
        root.addView(selectionList(
            items = AppPreferences.languages,
            selectedRawValue = AppPreferences.selectedLanguage(this).rawValue,
            rawValueFor = { it.rawValue },
            titleFor = { localizedLanguageName(it) },
            onSelect = {
                AppPreferences.setLanguage(this, it)
                reloadLibrary()
                showSettingsLanguage()
            }
        ), LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }

    private fun showSettingsAppearance() {
        screen = Screen.SettingsAppearance
        configureSystemBars(SurfaceMode.Shell)

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = pageBackground()
        }
        root.addView(toolbar(appString(R.string.settings_appearance), showBack = true), LinearLayout.LayoutParams(-1, dp(58)))
        root.addView(selectionList(
            items = AppPreferences.appearances,
            selectedRawValue = AppPreferences.selectedAppearance(this).rawValue,
            rawValueFor = { it.rawValue },
            titleFor = { localizedAppearanceName(it) },
            onSelect = {
                AppPreferences.setAppearance(this, it)
                showSettingsAppearance()
            }
        ), LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }

    private fun showViewer(page: WebPage, entry: WebPageEntry) {
        val entryFile = library.entryFileFor(page, entry)
        if (entry.source != WebPageEntrySource.BUNDLED_ARCHIVE_INDEX && !entryFile.exists()) {
            showMissingFile(page)
            return
        }

        configureSystemBars(SurfaceMode.Viewer)
        val root = FrameLayout(this).apply {
            setBackgroundColor(colors.pageTop)
        }
        val webView = WebView(this)
        val projectFolder = library.folderFor(page)
        val projectLoader = ProjectWebViewLoader(page, projectFolder)

        webView.settings.javaScriptEnabled = true
        webView.settings.domStorageEnabled = true
        webView.settings.allowFileAccess = false
        webView.settings.allowContentAccess = false
        webView.addJavascriptInterface(RuntimeStorageBridge(projectFolder), RUNTIME_BRIDGE_NAME)
        webView.setBackgroundColor(Color.TRANSPARENT)
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                view?.evaluateJavascript("window.__htmlAnywhereCaptureLocalStorage && window.__htmlAnywhereCaptureLocalStorage();", null)
                val activeEntry = entryForProjectUrl(page, url) ?: entry
                updateViewerEntry(activeEntry)
                library.markOpened(page, activeEntry)
            }

            override fun onReceivedError(
                view: WebView?,
                request: WebResourceRequest?,
                error: android.webkit.WebResourceError?
            ) {
                if (request?.isForMainFrame != false) library.markFailed(page, entry)
            }

            override fun shouldOverrideUrlLoading(view: WebView?, request: WebResourceRequest?): Boolean {
                val url = request?.url ?: return false
                if (ProjectWebViewLoader.isProjectUrl(page, url)) return false
                return if (url.scheme == "http" || url.scheme == "https") {
                    startActivity(Intent(Intent.ACTION_VIEW, url))
                    true
                } else {
                    false
                }
            }

            override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                val url = request?.url ?: return null
                return projectLoader.responseFor(url)
            }
        }
        webView.loadUrl(ProjectWebViewLoader.urlFor(page, entry.entryRelativePath).toString())
        root.addView(webView, FrameLayout.LayoutParams(-1, -1))
        val toolbar = viewerToolbar(page, entry, webView)
        root.addView(toolbar, FrameLayout.LayoutParams(-1, viewerTopChromeHeight(), Gravity.TOP))
        screen = Screen.Viewer(page.id, entry.id, webView, toolbar)
        applyViewerToolbarMode(toolbar, webView)
        setContentView(root)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        when (val current = screen) {
            is Screen.Viewer -> {
                configureSystemBars(SurfaceMode.Viewer)
                applyViewerToolbarMode(current.toolbar, current.webView)
            }
            is Screen.DeletedViewer -> {
                configureSystemBars(SurfaceMode.Viewer)
                applyViewerToolbarMode(current.toolbar, current.webView)
            }
            else -> Unit
        }
    }

    private fun showMissingFile(page: WebPage) {
        configureSystemBars(SurfaceMode.Shell)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            background = pageBackground()
        }
        root.addView(toolbar(appString(R.string.missing_file_title), showBack = true), LinearLayout.LayoutParams(-1, dp(58)))
        root.addView(missingCard(page), LinearLayout.LayoutParams(-1, 0, 1f))
        setContentView(root)
    }

    private fun projectList(): View {
        val recyclerView = RecyclerView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            clipToPadding = false
            setPadding(0, dp(8), 0, dp(116))
            layoutManager = LinearLayoutManager(this@MainActivity)
            adapter = PageRecyclerAdapter(library.pages) { page ->
                openPage(page)
            }
        }
        ItemTouchHelper(ProjectSwipeDeleteCallback(
            recyclerView.adapter as PageRecyclerAdapter,
            if (isRightToLeftLayout()) ItemTouchHelper.RIGHT else ItemTouchHelper.LEFT
        )).attachToRecyclerView(recyclerView)
        return recyclerView
    }

    private fun projectGrid(): View {
        val columns = homeGridColumnCount()
        return ScrollView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            clipToPadding = false
            setPadding(0, dp(14), 0, dp(116))
            addView(GridLayout(context).apply {
                columnCount = columns
                alignmentMode = GridLayout.ALIGN_BOUNDS
                useDefaultMargins = false
                val horizontalPadding = homeGridHorizontalPadding(columns)
                setPadding(horizontalPadding, 0, horizontalPadding, 0)
                library.pages.forEach { page ->
                    addView(projectGridItem(page), GridLayout.LayoutParams().apply {
                        width = 0
                        height = dp(108)
                        columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1f)
                        setMargins(0, 0, 0, dp(18))
                    })
                }
            }, ViewGroup.LayoutParams(-1, -2))
        }
    }

    private fun homeGridColumnCount(): Int {
        val widthDp = resources.configuration.screenWidthDp
        val landscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        return when {
            widthDp >= 840 || landscape && widthDp >= 700 -> 6
            widthDp >= 600 -> 5
            else -> 4
        }
    }

    private fun homeGridHorizontalPadding(columns: Int): Int {
        val widthDp = resources.configuration.screenWidthDp
        val paddingDp = when (columns) {
            4 -> (widthDp * 9 / 100).coerceIn(24, 40)
            5 -> (widthDp * 12 / 100).coerceIn(40, 90)
            else -> (widthDp * 14 / 100).coerceIn(64, 165)
        }
        return dp(paddingDp)
    }

    private fun projectGridItem(page: WebPage): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            setPadding(dp(4), 0, dp(4), 0)
            background = rippleRounded(Color.TRANSPARENT, dp(12).toFloat())
            setOnClickListener { openPage(page) }
            setOnLongClickListener {
                showProjectContextMenu(this, page)
                true
            }
            val iconSize = dp(64)
            ImageView(context).apply {
                setImageDrawable(projectIconDrawable(page, library.projectIconFileFor(page), colors.pageMiddle))
                scaleType = ImageView.ScaleType.FIT_CENTER
                addView(this, LinearLayout.LayoutParams(iconSize, iconSize))
            }
            TextView(context).apply {
                text = page.title
                textSize = 12f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.ink)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.MIDDLE
                gravity = Gravity.CENTER
                includeFontPadding = false
                addView(this, LinearLayout.LayoutParams(-1, dp(18)).apply { topMargin = dp(5) })
            }
        }
    }

    private fun recentlyDeletedList(): View {
        val adapter = RecentlyDeletedAdapter(recentlyDeletedItems()) { deletedPage ->
            if (deletedPage.page.opensInNativeFileViewer) {
                showDeletedNativeFileViewer(deletedPage)
            } else {
                showDeletedViewer(deletedPage, library.defaultEntry(deletedPage.page))
            }
        }
        val recyclerView = RecyclerView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            clipToPadding = false
            setPadding(0, dp(8), 0, dp(20))
            layoutManager = LinearLayoutManager(this@MainActivity)
            this.adapter = adapter
        }
        ItemTouchHelper(RecentlyDeletedSwipeCallback(adapter)).attachToRecyclerView(recyclerView)
        return recyclerView
    }

    private fun homeToolbar(onSearch: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(dp(16), 0, dp(8), 0)
            setBackgroundColor(Color.TRANSPARENT)

            addView(iconButton(R.drawable.ic_menu_24, appString(R.string.settings_title)) { showSettings() })

            TextView(context).apply {
                text = appString(R.string.app_name)
                textSize = 28f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.ink)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                gravity = Gravity.CENTER_VERTICAL or Gravity.START
                addView(this, LinearLayout.LayoutParams(0, -1, 1f))
            }

            addView(iconButton(R.drawable.ic_search_24, appString(R.string.search)) { onSearch() })
        }
    }

    private fun showSearchOverlay(host: FrameLayout) {
        if (screen != Screen.Home) return
        activeSearchOverlay?.dismiss(immediate = true)
        activeSearchOverlay = SearchOverlayController(host).also { it.show() }
    }

    private fun openSearchResult(result: WebPageSearchResult) {
        val page = library.page(result.page.id) ?: return
        if (page.opensInNativeFileViewer) {
            showNativeFileViewer(page)
            return
        }
        val entry = result.entry?.let { selected ->
            page.resolvedEntries().firstOrNull { it.id == selected.id }
        } ?: library.defaultEntry(page)
        showViewer(page, entry)
    }

    private inner class SearchOverlayController(
        private val host: FrameLayout
    ) {
        private val overlay = FrameLayout(this@MainActivity)
        private val input = EditText(this@MainActivity)
        private val resultsContainer = LinearLayout(this@MainActivity)
        private var isBuildingFullText = false

        fun show() {
            overlay.apply {
                setBackgroundColor(
                    if (colors.isDark) Color.argb(190, 8, 12, 18) else Color.argb(166, 246, 249, 252)
                )
                alpha = 0f
                setOnClickListener { dismiss() }
            }

            val card = searchCard()
            card.scaleX = 1.08f
            card.scaleY = 1.08f
            overlay.addView(
                card,
                FrameLayout.LayoutParams(
                    minOf(resources.displayMetrics.widthPixels - dp(32), dp(720)),
                    -2,
                    Gravity.TOP or Gravity.CENTER_HORIZONTAL
                ).apply { topMargin = dp(18) }
            )
            host.addView(overlay, FrameLayout.LayoutParams(-1, -1))
            updateResults()
            overlay.animate().alpha(1f).setDuration(160).start()
            card.animate().scaleX(1f).scaleY(1f).setDuration(160).start()
            input.requestFocus()
            showKeyboard(input)
        }

        fun dismiss(immediate: Boolean = false) {
            hideKeyboard(input)
            if (immediate) {
                host.removeView(overlay)
                if (activeSearchOverlay === this) activeSearchOverlay = null
                return
            }
            overlay.animate()
                .alpha(0f)
                .setDuration(140)
                .withEndAction {
                    host.removeView(overlay)
                    if (activeSearchOverlay === this) activeSearchOverlay = null
                }
                .start()
        }

        private fun searchCard(): View {
            return LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(10), dp(10), dp(10), dp(8))
                background = roundedDrawable(colors.surface, dp(18).toFloat(), strokeColor = colors.surfaceBorder)
                elevation = dp(10).toFloat()
                setOnClickListener { }
                addView(searchFieldRow(), LinearLayout.LayoutParams(-1, dp(48)))
                addView(ScrollView(context).apply {
                    setBackgroundColor(Color.TRANSPARENT)
                    isFillViewport = false
                    addView(resultsContainer.apply {
                        orientation = LinearLayout.VERTICAL
                        setPadding(0, dp(6), 0, 0)
                    }, ViewGroup.LayoutParams(-1, -2))
                }, LinearLayout.LayoutParams(-1, minOf(resources.displayMetrics.heightPixels / 2, dp(360))))
            }
        }

        private fun searchFieldRow(): View {
            return LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER_VERTICAL
                input.apply {
                    hint = appString(R.string.search_hint)
                    setSingleLine(true)
                    textSize = 17f
                    setTextColor(colors.ink)
                    setHintTextColor(colors.textSecondary)
                    background = rippleRounded(colors.surfaceInset, dp(12).toFloat(), strokeColor = colors.surfaceBorder)
                    setPaddingRelative(dp(14), 0, dp(14), 0)
                    addTextChangedListener(object : TextWatcher {
                        override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) = Unit
                        override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {
                            updateResults()
                        }
                        override fun afterTextChanged(s: Editable?) = Unit
                    })
                    addView(this, LinearLayout.LayoutParams(0, -1, 1f))
                }
                addView(iconButton(R.drawable.ic_close_24, appString(R.string.cancel)) { dismiss() })
            }
        }

        private fun updateResults() {
            val query = input.text?.toString().orEmpty()
            resultsContainer.removeAllViews()
            if (isBuildingFullText) {
                resultsContainer.addView(searchLoadingView(), LinearLayout.LayoutParams(-1, dp(96)))
                return
            }

            if (query.isBlank()) {
                val recommendations = searchIndex.recommendations(library)
                if (recommendations.isNotEmpty()) {
                    resultsContainer.addView(searchHeader(appString(R.string.search_recent)))
                    recommendations.forEach { addSearchResultRow(it, query) }
                } else {
                    resultsContainer.addView(searchEmptyView(query, allowFullText = false), LinearLayout.LayoutParams(-1, dp(168)))
                }
                return
            }

            val results = searchIndex.search(library, query)
            if (results.isEmpty()) {
                resultsContainer.addView(
                    searchEmptyView(query, allowFullText = !searchIndex.hasFullTextIndex),
                    LinearLayout.LayoutParams(-1, dp(190))
                )
            } else {
                results.forEach { addSearchResultRow(it, query) }
            }
        }

        private fun addSearchResultRow(result: WebPageSearchResult, query: String) {
            resultsContainer.addView(searchResultRow(result, query), LinearLayout.LayoutParams(-1, dp(74)))
        }

        private fun searchHeader(title: String): View {
            return TextView(this@MainActivity).apply {
                text = title
                textSize = 13f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.textSecondary)
                gravity = Gravity.START
                setPaddingRelative(dp(8), dp(6), dp(8), dp(4))
            }
        }

        private fun searchLoadingView(): View {
            return LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                gravity = Gravity.CENTER
                ProgressBar(context).apply {
                    isIndeterminate = true
                    addView(this, LinearLayout.LayoutParams(dp(26), dp(26)).apply { marginEnd = dp(10) })
                }
                TextView(context).apply {
                    text = appString(R.string.search_loading)
                    textSize = 16f
                    setTextColor(colors.textSecondary)
                    addView(this)
                }
            }
        }

        private fun searchEmptyView(query: String, allowFullText: Boolean): View {
            return LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER
                setPadding(dp(14), dp(10), dp(14), dp(10))
                TextView(context).apply {
                    text = appString(R.string.search_no_results_title)
                    textSize = 18f
                    typeface = Typeface.DEFAULT_BOLD
                    setTextColor(colors.ink)
                    gravity = Gravity.CENTER
                    addView(this, LinearLayout.LayoutParams(-1, -2))
                }
                TextView(context).apply {
                    text = if (allowFullText) {
                        appString(R.string.search_basic_only_message)
                    } else {
                        appString(R.string.search_no_results_message)
                    }
                    textSize = 14f
                    setTextColor(colors.textSecondary)
                    gravity = Gravity.CENTER
                    setPadding(0, dp(6), 0, 0)
                    addView(this, LinearLayout.LayoutParams(-1, -2))
                }
                if (allowFullText && query.isNotBlank()) {
                    Button(context).apply {
                        text = appString(R.string.search_all_file_content)
                        isAllCaps = false
                        textSize = 16f
                        typeface = Typeface.DEFAULT_BOLD
                        setTextColor(ACTION_BLUE_LABEL)
                        background = coloredActionButtonBackground(ACCENT_SKY)
                        setOnClickListener { buildFullTextIndex() }
                        addView(this, LinearLayout.LayoutParams(-1, dp(48)).apply { topMargin = dp(14) })
                    }
                }
            }
        }

        private fun buildFullTextIndex() {
            isBuildingFullText = true
            updateResults()
            Thread {
                runCatching { searchIndex.rebuild(library) }
                runOnUiThread {
                    if (activeSearchOverlay !== this) return@runOnUiThread
                    isBuildingFullText = false
                    updateResults()
                }
            }.start()
        }
    }

    private fun settingsContent(): View {
        return ScrollView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            clipToPadding = false
            val content = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(0, dp(8), 0, dp(28))
                addView(settingsSectionHeader(appString(R.string.settings_display)))
                addView(settingRow(
                    iconRes = R.drawable.icon_home,
                    tintIcon = false,
                    title = appString(R.string.settings_home_layout),
                    value = localizedHomeDisplayModeName(AppPreferences.selectedHomeDisplayMode(this@MainActivity)),
                    onClick = { showSettingsHomeLayout() }
                ))
                addView(settingRow(
                    iconRes = R.drawable.icon_dark_or_light,
                    tintIcon = false,
                    title = appString(R.string.settings_appearance),
                    value = localizedAppearanceName(AppPreferences.selectedAppearance(this@MainActivity)),
                    onClick = { showSettingsAppearance() }
                ))
                addView(settingRow(
                    iconRes = R.drawable.icon_earth,
                    tintIcon = false,
                    title = appString(R.string.settings_language),
                    value = localizedLanguageName(AppPreferences.selectedLanguage(this@MainActivity)),
                    onClick = { showSettingsLanguage() }
                ))
                /*
                上架前暂时隐藏支持入口；保留代码，待可评价和可分享的商店链接可用后再打开。
                addView(settingsSectionHeader(appString(R.string.settings_support)))
                addView(settingRow(
                    iconRes = R.drawable.icon_thumb_up_colored,
                    tintIcon = false,
                    title = appString(R.string.settings_rate),
                    value = null,
                    onClick = { openReviewPage() }
                ))
                addView(settingRow(
                    iconRes = R.drawable.icon_share_friends,
                    tintIcon = false,
                    title = appString(R.string.settings_share_app),
                    value = null,
                    onClick = { shareAppDownloadLink() }
                ))
                */
                addView(settingsSectionHeader(appString(R.string.settings_about)))
                addView(settingRow(
                    iconRes = R.drawable.icon_github,
                    tintIcon = false,
                    title = appString(R.string.settings_github),
                    value = null,
                    onClick = { openExternalLink(GITHUB_REPOSITORY_URL) }
                ))
                addView(settingRow(
                    iconRes = R.drawable.icon_discord,
                    tintIcon = false,
                    title = appString(R.string.settings_discord),
                    value = null,
                    onClick = { openExternalLink(DISCORD_URL) }
                ))
                addView(settingsSectionHeader(appString(R.string.settings_data)))
                addView(settingRow(
                    iconRes = R.drawable.icon_trash,
                    tintIcon = false,
                    title = appString(R.string.recently_deleted),
                    value = null,
                    onClick = { showRecentlyDeleted() }
                ))
                addView(versionFooter())
            }
            addView(content, ViewGroup.LayoutParams(-1, -2))
        }
    }

    private fun settingsSectionHeader(title: String): View {
        return TextView(this).apply {
            text = title
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(colors.textSecondary)
            includeFontPadding = false
            gravity = Gravity.START
            setPaddingRelative(dp(24), dp(18), dp(24), dp(8))
        }
    }

    private fun homeLayoutChooser(): View {
        return ScrollView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            clipToPadding = false
            val content = LinearLayout(context).apply {
                orientation = LinearLayout.HORIZONTAL
                isBaselineAligned = false
                setPadding(dp(18), dp(18), dp(18), dp(28))
                addView(
                    homeLayoutChoice("list", appString(R.string.settings_home_layout_list)),
                    LinearLayout.LayoutParams(0, -2, 1f).apply { rightMargin = dp(7) }
                )
                addView(
                    homeLayoutChoice("grid", appString(R.string.settings_home_layout_grid)),
                    LinearLayout.LayoutParams(0, -2, 1f).apply { leftMargin = dp(7) }
                )
            }
            addView(content, ViewGroup.LayoutParams(-1, -2))
        }
    }

    private fun homeLayoutChoice(modeRawValue: String, title: String): View {
        val selected = AppPreferences.selectedHomeDisplayMode(this).rawValue == modeRawValue
        return LinearLayout(this).apply choice@ {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            background = rippleRounded(Color.TRANSPARENT, dp(16).toFloat())
            setPadding(0, 0, 0, dp(8))
            contentDescription = title
            setOnClickListener {
                AppPreferences.homeDisplayModes.firstOrNull { it.rawValue == modeRawValue }?.let {
                    AppPreferences.setHomeDisplayMode(this@MainActivity, it)
                    showSettingsHomeLayout()
                }
            }

            FrameLayout(context).apply {
                background = roundedDrawable(colors.surfaceInset, dp(18).toFloat(), strokeColor = colors.surfaceBorder)
                addView(homeLayoutPreview(modeRawValue), FrameLayout.LayoutParams(-1, -1))
                this@choice.addView(this, LinearLayout.LayoutParams(-1, dp(142)))
            }
            TextView(context).apply {
                text = title
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.ink)
                gravity = Gravity.CENTER
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                includeFontPadding = false
                addView(this, LinearLayout.LayoutParams(-1, dp(20)).apply { topMargin = dp(10) })
            }
            ImageView(context).apply {
                if (selected) {
                    setImageResource(R.drawable.ic_check_24)
                    setColorFilter(Color.WHITE)
                }
                background = layoutChoiceMarkBackground(selected)
                scaleType = ImageView.ScaleType.CENTER
                addView(this, LinearLayout.LayoutParams(dp(26), dp(26)).apply { topMargin = dp(7) })
            }
        }
    }

    private fun homeLayoutPreview(modeRawValue: String): View {
        return if (modeRawValue == "grid") homeGridPreview() else homeListPreview()
    }

    private fun homeListPreview(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dp(12), dp(14), dp(12), dp(14))
            repeat(3) { index ->
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.HORIZONTAL
                    gravity = Gravity.CENTER_VERTICAL
                    background = roundedDrawable(colors.surface, dp(9).toFloat(), strokeColor = colors.surfaceBorder)
                    setPadding(dp(8), 0, dp(8), 0)
                    addView(View(context).apply {
                        background = roundedDrawable(colors.deepWater, dp(5).toFloat())
                    }, LinearLayout.LayoutParams(dp(18), dp(18)).apply { rightMargin = dp(8) })
                    addView(View(context).apply {
                        background = roundedDrawable(colors.ink, dp(3).toFloat())
                    }, LinearLayout.LayoutParams(0, dp(5), 1f))
                }, LinearLayout.LayoutParams(-1, dp(30)).apply {
                    if (index > 0) topMargin = dp(8)
                })
            }
        }
    }

    private fun homeGridPreview(): View {
        return GridLayout(this).apply {
            columnCount = 2
            setPadding(dp(24), dp(17), dp(24), dp(12))
            repeat(4) { index ->
                addView(LinearLayout(context).apply {
                    orientation = LinearLayout.VERTICAL
                    gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
                    addView(View(context).apply {
                        background = roundedDrawable(colors.deepWater, dp(9).toFloat())
                    }, LinearLayout.LayoutParams(dp(32), dp(32)))
                    addView(View(context).apply {
                        background = roundedDrawable(colors.ink, dp(3).toFloat())
                    }, LinearLayout.LayoutParams(dp(28), dp(4)).apply { topMargin = dp(5) })
                }, GridLayout.LayoutParams().apply {
                    width = 0
                    height = dp(54)
                    columnSpec = GridLayout.spec(GridLayout.UNDEFINED, 1f)
                    if (index >= 2) topMargin = dp(2)
                })
            }
        }
    }

    private fun layoutChoiceMarkBackground(selected: Boolean): Drawable {
        return if (selected) {
            GradientDrawable(
                GradientDrawable.Orientation.TOP_BOTTOM,
                intArrayOf(if (colors.isDark) 0xFF8EA1FF.toInt() else 0xFF90A0F4.toInt(), colors.deepWater)
            ).apply { shape = GradientDrawable.OVAL }
        } else {
            GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.TRANSPARENT)
                setStroke(dp(2), this@MainActivity.colors.surfaceBorder)
            }
        }
    }

    private fun settingRow(
        iconRes: Int,
        tintIcon: Boolean = true,
        title: String,
        value: String?,
        onClick: () -> Unit
    ): View {
        val rtl = isRightToLeftLayout()
        val outer = FrameLayout(this).apply {
            setPadding(dp(16), dp(5), dp(16), dp(5))
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(60)
            setPadding(if (rtl) dp(12) else dp(14), dp(10), if (rtl) dp(14) else dp(12), dp(10))
            background = rippleRounded(colors.surface, dp(12).toFloat(), strokeColor = colors.surfaceBorder)
            setOnClickListener { onClick() }
        }

        val iconView = ImageView(this).apply {
            setImageResource(iconRes)
            if (tintIcon) imageTintList = ColorStateList.valueOf(colors.deepWater)
            scaleType = ImageView.ScaleType.FIT_CENTER
        }

        val titleView = TextView(this).apply {
            text = title
            textSize = 17f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(colors.ink)
            maxLines = 1
            ellipsize = TextUtils.TruncateAt.END
            applyTextDirection(this)
            gravity = Gravity.CENTER_VERTICAL or Gravity.START
        }

        val valueView = value?.let {
            TextView(this).apply {
                text = value
                textSize = 15f
                setTextColor(colors.textSecondary)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                applyTextDirection(this)
                gravity = Gravity.CENTER_VERTICAL or Gravity.END
            }
        }

        val chevronView = chevronIconView()

        if (rtl) {
            root.addView(chevronView, LinearLayout.LayoutParams(dp(24), -1))
            valueView?.let {
                root.addView(it, LinearLayout.LayoutParams(-2, -2).apply { rightMargin = dp(10) })
            }
            root.addView(titleView, LinearLayout.LayoutParams(0, -2, 1f))
            root.addView(iconView, LinearLayout.LayoutParams(dp(28), dp(28)).apply { leftMargin = dp(12) })
        } else {
            root.addView(iconView, LinearLayout.LayoutParams(dp(28), dp(28)).apply { rightMargin = dp(12) })
            root.addView(titleView, LinearLayout.LayoutParams(0, -2, 1f))
            valueView?.let {
                root.addView(it, LinearLayout.LayoutParams(-2, -2).apply { leftMargin = dp(10) })
            }
            root.addView(chevronView, LinearLayout.LayoutParams(dp(24), -1))
        }

        outer.addView(root, FrameLayout.LayoutParams(-1, -2))
        return outer
    }

    private fun <T> selectionList(
        items: List<T>,
        selectedRawValue: String,
        rawValueFor: (T) -> String,
        titleFor: (T) -> String,
        onSelect: (T) -> Unit
    ): View {
        return ListView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            cacheColorHint = Color.TRANSPARENT
            divider = ColorDrawable(Color.TRANSPARENT)
            dividerHeight = 0
            selector = ColorDrawable(Color.TRANSPARENT)
            clipToPadding = false
            setPadding(0, dp(8), 0, dp(20))
            adapter = SelectionAdapter(items, selectedRawValue, rawValueFor, titleFor, onSelect)
        }
    }

    private fun versionFooter(): View {
        var lastTapAt = 0L
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(30), dp(16), dp(6))
            ImageView(context).apply {
                setImageResource(R.drawable.brand_logo_sticker)
                scaleType = ImageView.ScaleType.FIT_CENTER
                addView(this, LinearLayout.LayoutParams(dp(64), dp(64)))
            }
            TextView(context).apply {
                text = versionFooterText()
                textSize = 14f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.textSecondary)
                includeFontPadding = false
                addView(this, LinearLayout.LayoutParams(-2, -2).apply { topMargin = dp(10) })
            }
            setOnClickListener {
                val now = System.currentTimeMillis()
                if (now - lastTapAt < 500L) {
                    AppPreferences.setExpertModeEnabled(
                        this@MainActivity,
                        !AppPreferences.isExpertModeEnabled(this@MainActivity)
                    )
                    showSettings()
                }
                lastTapAt = now
            }
        }
    }

    private fun versionFooterText(): String {
        val info = packageManager.getPackageInfo(packageName, 0)
        val versionName = info.versionName ?: "0"
        val versionCode = if (Build.VERSION.SDK_INT >= 28) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
        return if (AppPreferences.isExpertModeEnabled(this)) "Ver $versionName ($versionCode)" else "Ver $versionName"
    }

    private fun localizedLanguageName(language: AppPreferences.Language): String {
        return if (language.rawValue == "automatic") appString(R.string.settings_option_automatic) else language.displayName
    }

    private fun localizedAppearanceName(appearance: AppPreferences.Appearance): String {
        return when (appearance.rawValue) {
            "light" -> appString(R.string.settings_option_light)
            "dark" -> appString(R.string.settings_option_dark)
            else -> appString(R.string.settings_option_automatic)
        }
    }

    private fun localizedHomeDisplayModeName(mode: AppPreferences.HomeDisplayMode): String {
        return when (mode.rawValue) {
            "grid" -> appString(R.string.settings_home_layout_grid)
            else -> appString(R.string.settings_home_layout_list)
        }
    }

    private fun openReviewPage() {
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(APP_REVIEW_URL)))
        }
    }

    private fun openExternalLink(url: String) {
        runCatching {
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
    }

    private fun shareAppDownloadLink() {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, APP_PRODUCT_URL)
        }
        startActivity(Intent.createChooser(intent, appString(R.string.settings_share_app)))
    }

    private fun toolbar(title: String, showBack: Boolean): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(dp(8), 0, dp(16), 0)
            setBackgroundColor(Color.TRANSPARENT)

            if (showBack) {
                addView(iconButton(R.drawable.ic_arrow_back_24, getString(android.R.string.cancel)) { onBackPressed() })
            }

            TextView(context).apply {
                text = title
                textSize = if (showBack) 19f else 28f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.ink)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                gravity = Gravity.CENTER_VERTICAL or Gravity.START
                addView(this, LinearLayout.LayoutParams(0, -1, 1f).apply {
                    marginStart = if (showBack) dp(4) else dp(8)
                })
            }
        }
    }

    private fun nativeFileViewerToolbar(page: WebPage, showActions: Boolean = true): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(dp(8), 0, dp(8), 0)
            setBackgroundColor(Color.TRANSPARENT)

            addView(iconButton(R.drawable.ic_arrow_back_24, getString(android.R.string.cancel)) { onBackPressed() })

            TextView(context).apply {
                text = page.title
                textSize = 19f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.ink)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.MIDDLE
                gravity = Gravity.CENTER_VERTICAL or Gravity.START
                addView(this, LinearLayout.LayoutParams(0, -1, 1f).apply { marginStart = dp(4) })
            }

            if (showActions) {
                addView(iconButton(R.drawable.ic_more_horiz_24, appString(R.string.more)) {
                    showNativeFileViewerMenu(this, page)
                })
            }
        }
    }

    private fun nativeFileList(projectFolder: File, files: List<WebPageProjectFile>, bottomPadding: Int): View {
        if (files.isEmpty()) return nativeFileEmptyState(bottomPadding)
        return ScrollView(this).apply {
            setBackgroundColor(Color.TRANSPARENT)
            clipToPadding = false
            setPadding(0, dp(8), 0, bottomPadding)
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                nativeFileGroups(files).forEach { group ->
                    group.title?.let { addView(nativeFileSectionHeader(it)) }
                    group.files.forEach { file ->
                        addView(nativeFileRow(projectFolder, file))
                    }
                }
            }, ViewGroup.LayoutParams(-1, -2))
        }
    }

    private fun nativeFileEmptyState(bottomReserved: Int): View {
        return FrameLayout(this).apply {
            setPadding(dp(20), dp(20), dp(20), bottomReserved)
            val card = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(18), dp(18), dp(18), dp(18))
                background = surfaceCardDrawable()
                elevation = dp(2).toFloat()
                addView(sectionTitle(appString(R.string.file_list_title), R.drawable.ic_folder_fill_24))
                TextView(context).apply {
                    text = appString(R.string.no_previewable_files)
                    textSize = 15f
                    setTextColor(colors.textSecondary)
                    gravity = Gravity.START
                    setPaddingRelative(0, dp(12), 0, 0)
                    addView(this)
                }
            }
            addView(card, FrameLayout.LayoutParams(-1, -2, Gravity.CENTER))
        }
    }

    private fun nativeFileSectionHeader(title: String): View {
        return TextView(this).apply {
            text = title
            textSize = 13f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(colors.textSecondary)
            includeFontPadding = false
            gravity = Gravity.START
            setPaddingRelative(dp(24), dp(16), dp(24), dp(6))
        }
    }

    private fun nativeFileRow(projectFolder: File, file: WebPageProjectFile): View {
        return row(
            iconRes = R.drawable.ic_doc_text_fill_24,
            iconDrawable = nativeFileKindIconDrawable(nativeFileKindFor(file)),
            title = file.fileName,
            subtitle = nativeFileSubtitle(file),
            statusText = null,
            showsChevron = true,
            openAction = { openNativeProjectFile(projectFolder, file) }
        )
    }

    private fun viewerToolbar(page: WebPage, entry: WebPageEntry, webView: WebView): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(dp(8), 0, dp(8), 0)
            addView(iconButton(R.drawable.ic_arrow_back_24, getString(android.R.string.cancel)) { onBackPressed() })
            addView(iconButton(R.drawable.ic_list_bullet_24, appString(R.string.page_directory)) {
                val currentPage = library.page(page.id) ?: page
                val currentEntry = currentViewerEntry(currentPage, entry)
                showEntryDirectory(this, currentPage, currentEntry, webView)
            }.apply {
                tag = page.resolvedEntries().size > 1
                visibility = if (page.resolvedEntries().size > 1) View.VISIBLE else View.GONE
            })
            TextView(context).apply {
                text = page.title
                textSize = 17f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.ink)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.MIDDLE
                gravity = Gravity.CENTER_VERTICAL or Gravity.START
                addView(this, LinearLayout.LayoutParams(0, -1, 1f).apply { marginStart = dp(4) })
            }
            addView(iconButton(R.drawable.ic_more_horiz_24, appString(R.string.more)) {
                val currentPage = library.page(page.id) ?: page
                showViewerMenu(this, currentPage, webView)
            })
        }
    }

    private fun applyViewerToolbarMode(toolbar: LinearLayout, webView: WebView) {
        val isLandscape = resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        (toolbar.layoutParams as? FrameLayout.LayoutParams)?.let { params ->
            params.height = if (isLandscape) dp(64) else viewerTopChromeHeight()
            params.gravity = Gravity.TOP
            toolbar.layoutParams = params
        }
        (webView.layoutParams as? FrameLayout.LayoutParams)?.let { params ->
            params.topMargin = if (isLandscape) 0 else viewerTopChromeHeight()
            webView.layoutParams = params
        }
        toolbar.gravity = if (isLandscape) Gravity.TOP or Gravity.START else Gravity.CENTER_VERTICAL
        toolbar.setPaddingRelative(dp(if (isLandscape) 12 else 8), if (isLandscape) dp(8) else 0, dp(8), 0)
        toolbar.background = ColorDrawable(if (isLandscape) Color.TRANSPARENT else colors.pageTop)

        val backButton = toolbar.getChildAt(0) as? ImageButton
        backButton?.background = if (isLandscape) {
            rippleRounded(VIEWER_FLOATING_CONTROL, dp(22).toFloat(), strokeColor = VIEWER_FLOATING_CONTROL_STROKE)
        } else {
            rippleRounded(Color.TRANSPARENT, dp(22).toFloat())
        }
        val directoryButton = toolbar.getChildAt(1)
        val hasDirectory = directoryButton?.tag == true
        directoryButton?.visibility = if (!isLandscape && hasDirectory) View.VISIBLE else View.GONE
        toolbar.getChildAt(2)?.visibility = if (isLandscape) View.GONE else View.VISIBLE
        toolbar.getChildAt(3)?.visibility = if (isLandscape) View.GONE else View.VISIBLE
    }

    private fun bottomDock(): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = roundedDrawable(colors.surfaceDock, topLeft = 28f, topRight = 28f)
            elevation = dp(8).toFloat()
            Button(context).apply {
                text = appString(R.string.open_web_file)
                isAllCaps = false
                textSize = 21f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(ACTION_BLUE_LABEL)
                background = actionButtonBackground()
                elevation = dp(3).toFloat()
                translationZ = dp(3).toFloat()
                stateListAnimator = null
                minHeight = 0
                minimumHeight = 0
                includeFontPadding = false
                gravity = Gravity.CENTER
                setOnClickListener { openFilePicker() }
                setOnTouchListener { view, event ->
                    when (event.actionMasked) {
                        android.view.MotionEvent.ACTION_DOWN -> {
                            view.animate().translationY(dp(2).toFloat()).setDuration(80).start()
                        }
                        android.view.MotionEvent.ACTION_UP,
                        android.view.MotionEvent.ACTION_CANCEL -> {
                            view.animate().translationY(0f).setDuration(100).start()
                        }
                    }
                    false
                }
                addView(this, LinearLayout.LayoutParams(-1, dp(64)))
            }
        }
    }

    private fun actionButton(title: String, fillColor: Int, labelColor: Int, onClick: () -> Unit): Button {
        return Button(this).apply {
            text = title
            isAllCaps = false
            textSize = 18f
            typeface = Typeface.DEFAULT_BOLD
            setTextColor(labelColor)
            background = coloredActionButtonBackground(fillColor)
            elevation = dp(3).toFloat()
            translationZ = dp(3).toFloat()
            stateListAnimator = null
            minHeight = 0
            minimumHeight = 0
            includeFontPadding = false
            gravity = Gravity.CENTER
            setOnClickListener { onClick() }
        }
    }

    private fun emptyState(): View {
        return emptyStatePrompt(
            title = appString(R.string.empty_title),
            message = appString(R.string.empty_message),
            fallbackIconRes = R.drawable.ic_doc_text_fill_24,
            bottomReserved = dp(100)
        )
    }

    private fun recentlyDeletedEmptyState(): View {
        return emptyStatePrompt(
            title = appString(R.string.no_recoverable_pages),
            message = appString(R.string.recently_deleted_empty_message),
            fallbackIconRes = R.drawable.ic_delete_24,
            bottomReserved = 0
        )
    }

    private fun emptyStatePrompt(
        title: String,
        message: String,
        fallbackIconRes: Int,
        bottomReserved: Int
    ): View {
        val prompt = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            addView(emptyStateIllustration(fallbackIconRes), LinearLayout.LayoutParams(dp(156), dp(156)))
            addView(EmptyStateBubbleView(context, colors.surface, colors.surfaceBorder), LinearLayout.LayoutParams(-1, -2).apply {
                topMargin = dp(14)
            })
            val bubble = getChildAt(1) as EmptyStateBubbleView
            bubble.setContent(title, message, colors.ink, colors.textSecondary)
        }
        return FrameLayout(this).apply {
            clipToPadding = false
            addView(prompt, FrameLayout.LayoutParams(-2, -2, Gravity.TOP or Gravity.CENTER_HORIZONTAL))
            val reposition = { positionEmptyStatePrompt(this, prompt, bottomReserved) }
            addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> reposition() }
            prompt.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ -> reposition() }
        }
    }

    private fun emptyStateIllustration(fallbackIconRes: Int): View {
        return FrameLayout(this).apply {
            addView(KeyedVideoIllustrationView(context, fallbackIconRes, colors.deepWater), FrameLayout.LayoutParams(-1, -1))
        }
    }

    private fun positionEmptyStatePrompt(viewport: FrameLayout, prompt: View, bottomReserved: Int) {
        if (viewport.width <= 0 || viewport.height <= 0) return
        val columnWidth = minOf(viewport.width, dp(720))
        val contentWidth = (columnWidth - dp(40)).coerceAtLeast(dp(220))
        val params = prompt.layoutParams as? FrameLayout.LayoutParams ?: return
        val nextWidth = minOf(contentWidth, (viewport.width - dp(40)).coerceAtLeast(dp(220)))
        if (params.width != nextWidth) {
            params.width = nextWidth
            prompt.layoutParams = params
            return
        }
        val promptHeight = prompt.measuredHeight
        if (promptHeight <= 0) return
        val availableHeight = (viewport.height - bottomReserved).coerceAtLeast(0)
        val topMargin = (availableHeight * 0.4f - promptHeight / 2f).toInt().coerceAtLeast(dp(12))
        val gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
        if (params.topMargin != topMargin || params.gravity != gravity) {
            params.topMargin = topMargin
            params.gravity = gravity
            prompt.layoutParams = params
        }
    }

    private fun missingCard(page: WebPage): View {
        return FrameLayout(this).apply {
            setPadding(dp(20), dp(20), dp(20), dp(20))
            val card = LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(18), dp(18), dp(18), dp(18))
                background = surfaceCardDrawable()
                elevation = dp(2).toFloat()
                addView(sectionTitle(appString(R.string.missing_file_title), android.R.drawable.ic_dialog_alert))
                TextView(context).apply {
                    text = appString(R.string.missing_file_message)
                    textSize = 15f
                    setTextColor(colors.textSecondary)
                    gravity = Gravity.START
                    setPaddingRelative(0, dp(12), 0, dp(16))
                    addView(this)
                }
                Button(context).apply {
                    text = appString(R.string.delete)
                    isAllCaps = false
                    typeface = Typeface.DEFAULT_BOLD
                    setTextColor(ACTION_CORAL_LABEL)
                    background = rippleRounded(ACCENT_CORAL, dp(8).toFloat())
                    setOnClickListener {
                        library.delete(page)
                        showHome()
                    }
                    addView(this, LinearLayout.LayoutParams(-1, dp(44)))
                }
            }
            addView(card, FrameLayout.LayoutParams(-1, -2, Gravity.CENTER))
        }
    }

    private fun sectionTitle(title: String, iconRes: Int): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            ImageView(context).apply {
                setImageResource(iconRes)
                imageTintList = ColorStateList.valueOf(colors.deepWater)
                addView(this, LinearLayout.LayoutParams(dp(24), dp(24)))
            }
            TextView(context).apply {
                text = title
                textSize = 20f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.ink)
                gravity = Gravity.START
                addView(this, LinearLayout.LayoutParams(0, -2, 1f).apply { marginStart = dp(10) })
            }
        }
    }

    private fun showViewerMenu(anchor: View, page: WebPage, webView: WebView) {
        PopupMenu(this, anchor).apply {
            menu.add(Menu.NONE, 1, 1, R.string.refresh).setIcon(R.drawable.ic_refresh_24)
            menu.add(Menu.NONE, 2, 2, R.string.share).setIcon(R.drawable.ic_share_24)
            menu.add(Menu.NONE, 3, 3, R.string.rename).setIcon(R.drawable.ic_edit_24)
            menu.add(Menu.NONE, 4, 4, R.string.clear_cache).setIcon(R.drawable.ic_delete_24)
            setOnMenuItemClickListener { item: MenuItem ->
                when (item.itemId) {
                    1 -> webView.reload()
                    2 -> shareProject(page)
                    3 -> renamePage(page) { refreshed -> updateViewerProjectTitle(refreshed.title) }
                    4 -> confirmClearRuntimeStorage(page, webView)
                }
                true
            }
            showWithOptionalIcons()
        }
    }

    private fun showNativeFileViewerMenu(anchor: View, page: WebPage) {
        PopupMenu(this, anchor).apply {
            menu.add(Menu.NONE, 1, 1, R.string.share).setIcon(R.drawable.ic_share_24)
            menu.add(Menu.NONE, 2, 2, R.string.rename).setIcon(R.drawable.ic_edit_24)
            menu.add(Menu.NONE, 3, 3, R.string.delete).setIcon(R.drawable.ic_delete_24)
            setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    1 -> shareProject(page)
                    2 -> renamePage(page) { refreshed -> showNativeFileViewer(refreshed) }
                    3 -> confirmDeletePage(page)
                }
                true
            }
            showWithOptionalIcons()
        }
    }

    private fun PopupMenu.showWithOptionalIcons() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            setForceShowIcon(true)
        }
        show()
    }

    private fun showEntryDirectory(anchor: View, page: WebPage, currentEntry: WebPageEntry, webView: WebView) {
        showEntryDirectoryPopup(anchor, page.resolvedEntries(), currentEntry.id) { selected ->
            updateViewerEntry(selected)
            webView.loadUrl(ProjectWebViewLoader.urlFor(page, selected.entryRelativePath).toString())
        }
    }

    private fun showDeletedEntryDirectory(
        anchor: View,
        deletedPage: DeletedWebPage,
        currentEntry: WebPageEntry,
        webView: WebView
    ) {
        showEntryDirectoryPopup(anchor, deletedPage.page.resolvedEntries(), currentEntry.id) { selected ->
            updateDeletedViewerEntry(selected)
            webView.loadUrl(ProjectWebViewLoader.urlFor(deletedPage.page, selected.entryRelativePath).toString())
        }
    }

    private fun showEntryDirectoryPopup(
        anchor: View,
        entries: List<WebPageEntry>,
        currentEntryID: String,
        onSelect: (WebPageEntry) -> Unit
    ) {
        val popupWidth = minOf(dp(320), (resources.displayMetrics.widthPixels - dp(32)).coerceAtLeast(dp(240)))
        val popupHeight = minOf(entries.size * dp(59) + dp(16), dp(420))
        lateinit var popup: PopupWindow
        val content = ScrollView(this).apply {
            isFillViewport = false
            setBackgroundColor(Color.TRANSPARENT)
            addView(LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                setPadding(dp(8), dp(8), dp(8), dp(8))
                background = roundedDrawable(colors.surface, dp(16).toFloat(), strokeColor = colors.surfaceBorder)
                entries.forEach { entry ->
                    addView(directoryEntryRow(entry, entry.id == currentEntryID) {
                        popup.dismiss()
                        onSelect(entry)
                    }, LinearLayout.LayoutParams(-1, dp(59)))
                }
            }, FrameLayout.LayoutParams(-1, -2))
        }
        popup = PopupWindow(content, popupWidth, popupHeight, true).apply {
            isOutsideTouchable = true
            setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            elevation = dp(8).toFloat()
        }
        popup.showAsDropDown(anchor, -(popupWidth - anchor.width).coerceAtLeast(0), dp(2))
    }

    private fun directoryEntryRow(entry: WebPageEntry, isCurrent: Boolean, onClick: () -> Unit): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(dp(12), dp(7), dp(8), dp(7))
            background = rippleRounded(Color.TRANSPARENT, dp(10).toFloat())
            setOnClickListener { onClick() }
            LinearLayout(context).apply {
                orientation = LinearLayout.VERTICAL
                TextView(context).apply {
                    text = entry.title
                    textSize = 17f
                    typeface = Typeface.DEFAULT_BOLD
                    setTextColor(colors.ink)
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.MIDDLE
                    addView(this, LinearLayout.LayoutParams(-1, -2))
                }
                TextView(context).apply {
                    text = if (entry.lastLoadStatus == WebPageLoadStatus.READY) {
                        entry.entryFileName
                    } else {
                        "${entry.entryFileName} · ${statusText(entry.lastLoadStatus)}"
                    }
                    textSize = 14f
                    setTextColor(colors.textSecondary)
                    maxLines = 1
                    ellipsize = TextUtils.TruncateAt.END
                    addView(this, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(2) })
                }
                addView(this, LinearLayout.LayoutParams(0, -2, 1f))
            }
            ImageView(context).apply {
                setImageResource(R.drawable.ic_check_24)
                imageTintList = ColorStateList.valueOf(colors.deepWater)
                visibility = if (isCurrent) View.VISIBLE else View.INVISIBLE
                addView(this, LinearLayout.LayoutParams(dp(28), dp(28)).apply { marginStart = dp(8) })
            }
        }
    }

    private fun showProjectContextMenu(anchor: View, page: WebPage) {
        PopupMenu(this, anchor).apply {
            menu.add(Menu.NONE, 1, 1, R.string.open)
            menu.add(Menu.NONE, 2, 2, R.string.rename)
            menu.add(Menu.NONE, 3, 3, R.string.set_icon)
            menu.add(Menu.NONE, 4, 4, R.string.delete)
            setOnMenuItemClickListener { item ->
                when (item.itemId) {
                    1 -> openPage(page)
                    2 -> renamePage(page)
                    3 -> chooseProjectIconSource(page)
                    4 -> confirmDeletePage(page)
                }
                true
            }
            show()
        }
    }

    private fun chooseProjectIconSource(page: WebPage) {
        AlertDialog.Builder(this)
            .setTitle(appString(R.string.set_icon))
            .setItems(arrayOf(appString(R.string.choose_from_photos), appString(R.string.choose_from_files))) { _, which ->
                projectIconTargetPageID = page.id
                if (which == 0) openProjectIconPhotoPicker() else openProjectIconFilePicker()
            }
            .show()
    }

    private fun openProjectIconPhotoPicker() {
        val intent = Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
            type = "image/*"
        }
        startActivityForResult(intent, projectIconPhotoRequestCode)
    }

    private fun openProjectIconFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
        }
        startActivityForResult(intent, projectIconFileRequestCode)
    }

    private fun setProjectIconFromUri(uri: Uri) {
        val page = projectIconTargetPageID?.let { library.page(it) }
        projectIconTargetPageID = null
        if (page == null) return
        val bytes = runCatching {
            contentResolver.openInputStream(uri)?.use { it.readBytes() }
        }.getOrNull()
        if (bytes == null || !library.setCustomProjectIcon(page, bytes)) {
            AlertDialog.Builder(this)
                .setTitle(appString(R.string.set_icon_failed_title))
                .setPositiveButton(appString(R.string.ok), null)
                .show()
            return
        }
        showHome()
    }

    private fun confirmDeletePage(page: WebPage) {
        AlertDialog.Builder(this)
            .setTitle(appString(R.string.delete_title))
            .setMessage(appString(R.string.delete_to_recently_deleted_message))
            .setNegativeButton(appString(R.string.cancel), null)
            .setPositiveButton(appString(R.string.delete)) { _, _ ->
                library.delete(page)
                showHome()
            }
            .show()
    }

    private fun deletedViewerToolbar(deletedPage: DeletedWebPage, entry: WebPageEntry, webView: WebView): LinearLayout {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPaddingRelative(dp(8), 0, dp(8), 0)
            addView(iconButton(R.drawable.ic_arrow_back_24, getString(android.R.string.cancel)) { onBackPressed() })
            addView(iconButton(R.drawable.ic_list_bullet_24, appString(R.string.page_directory)) {
                val currentEntry = currentDeletedViewerEntry(deletedPage.page, entry)
                showDeletedEntryDirectory(this, deletedPage, currentEntry, webView)
            }.apply {
                tag = deletedPage.page.resolvedEntries().size > 1
                visibility = if (deletedPage.page.resolvedEntries().size > 1) View.VISIBLE else View.GONE
            })
            TextView(context).apply {
                text = deletedPage.page.title
                textSize = 17f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.ink)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.MIDDLE
                gravity = Gravity.CENTER_VERTICAL or Gravity.START
                addView(this, LinearLayout.LayoutParams(0, -1, 1f).apply { marginStart = dp(4) })
            }
        }
    }

    private fun recentlyDeletedActionDock(deletedPage: DeletedWebPage): View {
        return LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            setPadding(dp(16), dp(14), dp(16), dp(14))
            background = roundedDrawable(colors.surfaceDock, topLeft = 28f, topRight = 28f)
            elevation = dp(8).toFloat()
            addView(actionButton(appString(R.string.restore), ACCENT_LEAF, ACTION_LEAF_LABEL) {
                restoreDeletedPage(deletedPage)
            }, LinearLayout.LayoutParams(0, dp(64), 1f).apply { marginEnd = dp(8) })
            addView(actionButton(appString(R.string.delete_permanently), ACCENT_CORAL, ACTION_CORAL_LABEL) {
                confirmPermanentlyDelete(deletedPage)
            }, LinearLayout.LayoutParams(0, dp(64), 1f).apply { marginStart = dp(8) })
        }
    }

    private fun currentViewerEntry(page: WebPage, fallback: WebPageEntry): WebPageEntry {
        val activeEntryID = (screen as? Screen.Viewer)?.entryID
        return activeEntryID?.let { id ->
            page.resolvedEntries().firstOrNull { it.id == id }
        } ?: fallback
    }

    private fun currentDeletedViewerEntry(page: WebPage, fallback: WebPageEntry): WebPageEntry {
        val activeEntryID = (screen as? Screen.DeletedViewer)?.entryID
        return activeEntryID?.let { id ->
            page.resolvedEntries().firstOrNull { it.id == id }
        } ?: fallback
    }

    private fun entryForProjectUrl(page: WebPage, rawUrl: String?): WebPageEntry? {
        val url = rawUrl?.let { runCatching { Uri.parse(it) }.getOrNull() } ?: return null
        val relativePath = ProjectWebViewLoader.relativePathFor(page, url) ?: return null
        return page.resolvedEntries().firstOrNull { it.entryRelativePath == relativePath }
    }

    private fun updateViewerEntry(entry: WebPageEntry) {
        val current = screen as? Screen.Viewer ?: return
        if (current.entryID != entry.id) {
            screen = current.copy(entryID = entry.id)
        }
    }

    private fun updateDeletedViewerEntry(entry: WebPageEntry) {
        val current = screen as? Screen.DeletedViewer ?: return
        if (current.entryID != entry.id) {
            screen = current.copy(entryID = entry.id)
        }
    }

    private fun updateViewerProjectTitle(title: String) {
        val current = screen as? Screen.Viewer ?: return
        (current.toolbar.getChildAt(2) as? TextView)?.text = title
    }

    private fun shareProject(page: WebPage) {
        try {
            val shareFile = ShareExporter(File(cacheDir, "shares")).shareFileForProject(library.folderFor(page), page.title)
            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", shareFile.file)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = if (shareFile.isArchive) "application/zip" else mimeTypeForFile(shareFile.file)
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, appString(R.string.share)))
        } catch (_: Throwable) {
            showError(appString(R.string.share_failed))
        }
    }

    private fun confirmClearRuntimeStorage(page: WebPage, webView: WebView) {
        AlertDialog.Builder(this)
            .setTitle(appString(R.string.clear_cache_title))
            .setMessage(appString(R.string.clear_cache_message))
            .setNegativeButton(appString(R.string.cancel), null)
            .setPositiveButton(appString(R.string.clear)) { _, _ ->
                try {
                    val projectFolder = library.folderFor(page)
                    WebPageRuntimeStorage.clearRuntimeData(projectFolder)
                    WebStorage.getInstance().deleteOrigin(ProjectWebViewLoader.originFor(page))
                    webView.evaluateJavascript("try { localStorage.clear(); } catch (error) {}", null)
                    webView.reload()
                } catch (_: Throwable) {
                    AlertDialog.Builder(this)
                        .setTitle(appString(R.string.clear_cache_failed_title))
                        .setMessage(appString(R.string.clear_cache_failed))
                        .setPositiveButton(appString(R.string.ok), null)
                        .show()
                }
            }
            .show()
    }

    private fun restoreDeletedPage(deletedPage: DeletedWebPage) {
        try {
            library.restore(deletedPage)
            showRecentlyDeleted()
        } catch (error: WebPageLibraryException) {
            AlertDialog.Builder(this)
                .setTitle(appString(R.string.missing_file_title))
                .setMessage(error.message ?: appString(R.string.recoverable_file_missing))
                .setPositiveButton(appString(R.string.ok), null)
                .show()
        }
    }

    private fun confirmPermanentlyDelete(deletedPage: DeletedWebPage) {
        AlertDialog.Builder(this)
            .setTitle(appString(R.string.delete_permanently_title))
            .setMessage(appString(R.string.delete_permanently_message))
            .setNegativeButton(appString(R.string.cancel), null)
            .setPositiveButton(appString(R.string.delete_permanently)) { _, _ ->
                library.permanentlyDelete(deletedPage)
                showRecentlyDeleted()
            }
            .show()
    }

    private fun renamePage(page: WebPage, onRenamed: ((WebPage) -> Unit)? = null) {
        val input = EditText(this).apply {
            setText(page.title)
            selectAll()
            hint = appString(R.string.project_name)
        }
        AlertDialog.Builder(this)
            .setTitle(appString(R.string.rename_project))
            .setView(input)
            .setNegativeButton(appString(R.string.cancel), null)
            .setPositiveButton(appString(R.string.save)) { _, _ ->
                if (library.renamePage(page, input.text.toString())) {
                    val refreshed = library.page(page.id) ?: page
                    if (onRenamed != null) onRenamed(refreshed) else showHome()
                }
            }
            .show()
    }

    private fun openFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        startActivityForResult(intent, openFileRequestCode)
    }

    private fun showError(message: String) {
        AlertDialog.Builder(this)
            .setTitle(appString(R.string.error_open_title))
            .setMessage(message)
            .setPositiveButton(appString(R.string.ok), null)
            .show()
    }

    private fun statusText(status: WebPageLoadStatus): String {
        return when (status) {
            WebPageLoadStatus.READY -> appString(R.string.status_ready)
            WebPageLoadStatus.MISSING -> appString(R.string.status_missing)
            WebPageLoadStatus.FAILED -> appString(R.string.status_failed)
        }
    }

    private fun nativeFileGroups(files: List<WebPageProjectFile>): List<NativeFileGroup> {
        return files
            .groupBy { nativeFileDirectoryPath(it.relativePath) }
            .map { (directoryPath, groupFiles) ->
                NativeFileGroup(
                    directoryPath = directoryPath,
                    files = groupFiles.sortedBy { it.relativePath.lowercase() }
                )
            }
            .sortedWith(compareBy<NativeFileGroup> { if (it.directoryPath.isBlank()) 0 else 1 }
                .thenBy(String.CASE_INSENSITIVE_ORDER) { it.directoryPath })
    }

    private fun nativeFileDirectoryPath(relativePath: String): String {
        val parts = relativePath.split('/').filter { it.isNotBlank() }
        if (parts.size <= 1) return ""
        return parts.dropLast(1).joinToString("/")
    }

    private fun nativeFileSubtitle(file: WebPageProjectFile): String {
        val size = formattedByteCount(file.byteCount)
        return if (file.relativePath == file.fileName) size else "${file.relativePath} · $size"
    }

    private fun nativeFileKindFor(file: WebPageProjectFile): NativeFileKind {
        val extension = File(file.relativePath).extension.lowercase()
        return when (extension) {
            "png", "jpg", "jpeg", "gif", "webp", "svg", "ico", "heic", "heif" -> NativeFileKind.IMAGE
            "mp4", "m4v", "mov", "webm", "avi", "mkv", "3gp" -> NativeFileKind.VIDEO
            "mp3", "m4a", "wav", "aac", "ogg", "flac" -> NativeFileKind.AUDIO
            "pdf" -> NativeFileKind.PDF
            "txt", "text", "lrc", "md", "markdown", "csv", "tsv", "log",
            "json", "xml", "yaml", "yml", "ini", "conf", "cfg", "srt", "ass",
            "ssa", "vtt", "css", "js", "mjs", "ts" -> NativeFileKind.TEXT
            "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtf" -> NativeFileKind.DOCUMENT
            else -> NativeFileKind.OTHER
        }
    }

    private fun nativeFileKindIconDrawable(kind: NativeFileKind): Drawable {
        val glyphRes = when (kind) {
            NativeFileKind.IMAGE -> android.R.drawable.ic_menu_gallery
            NativeFileKind.VIDEO, NativeFileKind.AUDIO -> android.R.drawable.ic_media_play
            NativeFileKind.PDF, NativeFileKind.TEXT, NativeFileKind.DOCUMENT, NativeFileKind.OTHER -> R.drawable.ic_doc_text_fill_24
        }
        val tint = when (kind) {
            NativeFileKind.IMAGE -> ACCENT_SKY
            NativeFileKind.VIDEO -> ACCENT_AI_PURPLE
            NativeFileKind.AUDIO -> ACCENT_MINT
            NativeFileKind.PDF -> ACCENT_CORAL
            NativeFileKind.TEXT, NativeFileKind.DOCUMENT -> colors.deepWater
            NativeFileKind.OTHER -> colors.textSecondary
        }
        return NativeFileKindDrawable(
            glyph = getDrawable(glyphRes)?.mutate(),
            fillColor = Color.argb(36, Color.red(tint), Color.green(tint), Color.blue(tint)),
            tintColor = tint
        )
    }

    private fun openNativeProjectFile(projectFolder: File, file: WebPageProjectFile) {
        val target = projectFileFor(projectFolder, file.relativePath)
        if (target == null || !target.exists()) {
            showCannotPreviewFile()
            return
        }
        when (nativeFileKindFor(file)) {
            NativeFileKind.IMAGE -> {
                if (!showNativeImagePreview(target)) openSystemPreview(target)
            }
            NativeFileKind.TEXT -> showNativeTextPreview(target)
            NativeFileKind.OTHER -> {
                if (canPreviewText(target)) showNativeTextPreview(target) else openSystemPreview(target)
            }
            NativeFileKind.VIDEO,
            NativeFileKind.AUDIO,
            NativeFileKind.PDF,
            NativeFileKind.DOCUMENT -> openSystemPreview(target)
        }
    }

    private fun projectFileFor(projectFolder: File, relativePath: String): File? {
        val safePath = runCatching { ZipTools.safeRelativePath(relativePath) }.getOrNull() ?: return null
        val file = File(projectFolder, safePath)
        return if (ZipTools.isDescendant(file, projectFolder) && file.isFile) file else null
    }

    private fun showNativeImagePreview(file: File): Boolean {
        val bitmap = runCatching { BitmapFactory.decodeFile(file.absolutePath) }.getOrNull() ?: return false
        val imageView = ImageView(this).apply {
            setImageBitmap(bitmap)
            adjustViewBounds = true
            setMaxHeight((resources.displayMetrics.heightPixels * 0.72f).toInt())
            scaleType = ImageView.ScaleType.FIT_CENTER
            setBackgroundColor(Color.BLACK)
            setPadding(0, dp(12), 0, dp(12))
        }
        AlertDialog.Builder(this)
            .setTitle(file.name)
            .setView(imageView)
            .setPositiveButton(appString(R.string.ok), null)
            .show()
        return true
    }

    private fun showNativeTextPreview(file: File) {
        val text = previewText(file)
        if (text == null) {
            openSystemPreview(file)
            return
        }
        val scrollView = ScrollView(this).apply {
            setBackgroundColor(colors.pageBottom)
            addView(TextView(context).apply {
                this.text = text
                textSize = 15f
                typeface = Typeface.MONOSPACE
                setTextColor(colors.ink)
                setTextIsSelectable(true)
                setPadding(dp(16), dp(16), dp(16), dp(16))
            }, ViewGroup.LayoutParams(-1, -2))
        }
        AlertDialog.Builder(this)
            .setTitle(file.name)
            .setView(scrollView)
            .setPositiveButton(appString(R.string.ok), null)
            .show()
    }

    private fun openSystemPreview(file: File) {
        try {
            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeTypeForFile(file))
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(intent, file.name))
        } catch (_: ActivityNotFoundException) {
            showCannotPreviewFile()
        } catch (_: Throwable) {
            showCannotPreviewFile()
        }
    }

    private fun showCannotPreviewFile() {
        AlertDialog.Builder(this)
            .setTitle(appString(R.string.cannot_preview_file_title))
            .setMessage(appString(R.string.cannot_preview_file_message))
            .setPositiveButton(appString(R.string.ok), null)
            .show()
    }

    private fun canPreviewText(file: File): Boolean {
        return previewText(file, maximumByteCount = 4096) != null
    }

    private fun previewText(file: File, maximumByteCount: Int = 5 * 1024 * 1024): String? {
        val length = file.length()
        val readLimit = minOf(maxOf(length, 1L), maximumByteCount.toLong()).toInt()
        val data = ByteArray(readLimit)
        val count = runCatching {
            FileInputStream(file).use { stream -> stream.read(data) }
        }.getOrDefault(-1)
        if (count < 0) return null
        if (count == 0) return ""
        val prefix = data.copyOf(count)
        val decoded = decodedText(prefix) ?: return null
        return if (length > maximumByteCount) "$decoded\n\n..." else decoded
    }

    private fun decodedText(data: ByteArray): String? {
        if (looksBinary(data)) return null
        val charsets = listOf(
            Charsets.UTF_8,
            Charsets.UTF_16,
            Charsets.UTF_16LE,
            Charsets.UTF_16BE,
            Charsets.ISO_8859_1
        )
        for (charset in charsets) {
            val decoded = runCatching {
                charset.newDecoder()
                    .onMalformedInput(CodingErrorAction.REPORT)
                    .onUnmappableCharacter(CodingErrorAction.REPORT)
                    .decode(ByteBuffer.wrap(data))
                    .toString()
            }.getOrNull()
            if (decoded != null) return decoded
        }
        return null
    }

    private fun looksBinary(data: ByteArray): Boolean {
        var controlByteCount = 0
        for (byte in data) {
            val value = byte.toInt() and 0xff
            if (value == 0) return true
            if (value < 0x09 || value in 0x0e..0x1f) {
                controlByteCount += 1
            }
        }
        return controlByteCount > maxOf(8, data.size / 100)
    }

    private fun mimeTypeForFile(file: File): String {
        val extension = file.extension.lowercase()
        return when (extension) {
            "html", "htm" -> "text/html"
            "js" -> "text/javascript"
            "css" -> "text/css"
            "svg" -> "image/svg+xml"
            else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
        }
    }

    private fun formattedByteCount(byteCount: Long): String {
        val units = arrayOf("B", "KB", "MB", "GB")
        var value = byteCount.toDouble()
        var unitIndex = 0
        while (value >= 1024.0 && unitIndex < units.lastIndex) {
            value /= 1024.0
            unitIndex += 1
        }
        val decimals = if (unitIndex == 0 || value >= 10.0) 0 else 1
        return "%.${decimals}f %s".format(value, units[unitIndex])
    }

    private fun searchResultRow(result: WebPageSearchResult, query: String): View {
        val page = library.page(result.page.id) ?: result.page
        val subtitle = result.snippet?.takeIf { it.isNotBlank() } ?: result.subtitle
        return row(
            iconRes = if (page.resolvedEntries().size > 1) R.drawable.ic_folder_fill_24 else R.drawable.ic_doc_text_fill_24,
            iconDrawable = projectIconDrawable(page, library.projectIconFileFor(page), colors.surface),
            title = highlightedText(result.title, query),
            subtitle = highlightedText(subtitle, query),
            statusText = null,
            showsChevron = true,
            openAction = {
                activeSearchOverlay?.dismiss(immediate = true)
                openSearchResult(result)
            }
        )
    }

    private fun highlightedText(text: String, query: String): CharSequence {
        if (query.isBlank()) return text
        val start = text.indexOf(query, ignoreCase = true)
        if (start < 0) return text
        val end = start + query.length
        return SpannableString(text).apply {
            setSpan(ForegroundColorSpan(colors.deepWater), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            setSpan(StyleSpan(Typeface.BOLD), start, end, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    private fun showKeyboard(view: View) {
        view.post {
            (getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager)
                ?.showSoftInput(view, InputMethodManager.SHOW_IMPLICIT)
        }
    }

    private fun hideKeyboard(view: View) {
        (getSystemService(INPUT_METHOD_SERVICE) as? InputMethodManager)
            ?.hideSoftInputFromWindow(view.windowToken, 0)
    }

    private fun searchIndexFile(): File {
        return File(filesDir, "HTMLKeep/search-index.json")
    }

    private fun libraryStrings(): WebPageLibrary.LibraryStrings {
        return WebPageLibrary.LibraryStrings(
            unsupportedFile = appString(R.string.unsupported_file),
            unreadableFile = appString(R.string.unreadable_file),
            archiveMissingHtml = appString(R.string.archive_missing_html),
            archiveExtractFailed = appString(R.string.archive_extract_failed),
            storageFailed = appString(R.string.storage_failed),
            untitledWebPage = appString(R.string.untitled_web_page),
            missingRecoverableFolder = appString(R.string.recoverable_file_missing),
            fileListTitle = appString(R.string.file_list_title),
            importFileTooLarge = appString(R.string.import_file_too_large)
        )
    }

    private fun reloadLibrary() {
        library = WebPageLibrary(File(filesDir, "HTMLKeep"), libraryStrings())
    }

    private fun projectIconDrawable(page: WebPage, iconFile: File?, hostColor: Int): Drawable {
        val entry = library.defaultEntry(page)
        return projectIconDrawable(
            entriesCount = page.resolvedEntries().size,
            iconFile = iconFile,
            topColor = entry.safeAreaTopColor ?: page.safeAreaTopColor,
            bottomColor = entry.safeAreaBottomColor ?: page.safeAreaBottomColor,
            hostColor = hostColor
        )
    }

    private fun projectIconDrawable(deletedPage: DeletedWebPage, iconFile: File?, hostColor: Int): Drawable {
        val entry = library.defaultEntry(deletedPage.page)
        return projectIconDrawable(
            entriesCount = deletedPage.page.resolvedEntries().size,
            iconFile = iconFile,
            topColor = entry.safeAreaTopColor ?: deletedPage.page.safeAreaTopColor,
            bottomColor = entry.safeAreaBottomColor ?: deletedPage.page.safeAreaBottomColor,
            hostColor = hostColor
        )
    }

    private fun projectIconDrawable(
        entriesCount: Int,
        iconFile: File?,
        topColor: String?,
        bottomColor: String?,
        hostColor: Int
    ): Drawable {
        val bitmap = iconFile?.let { runCatching { BitmapFactory.decodeFile(it.absolutePath) }.getOrNull() }
        val glyphRes = if (entriesCount > 1) R.drawable.ic_folder_fill_24 else R.drawable.ic_doc_text_fill_24
        return ProjectIconDrawable(
            bitmap = bitmap,
            glyph = getDrawable(glyphRes)?.mutate(),
            topColor = parseProjectIconColor(topColor),
            bottomColor = parseProjectIconColor(bottomColor),
            fallbackBackground = colors.surface,
            fallbackInk = colors.ink,
            hostColor = hostColor
        )
    }

    private fun parseProjectIconColor(value: String?): Int? {
        return value?.takeIf { it.isNotBlank() }?.let {
            runCatching { Color.parseColor(it) }.getOrNull()
        }
    }

    private fun row(
        iconRes: Int,
        iconFile: File? = null,
        iconDrawable: Drawable? = null,
        title: CharSequence,
        subtitle: CharSequence,
        statusText: String?,
        showsChevron: Boolean = false,
        openAction: () -> Unit
    ): View {
        val rtl = isRightToLeftLayout()
        val outer = FrameLayout(this).apply {
            setPadding(dp(16), dp(6), dp(16), dp(6))
        }
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            gravity = Gravity.CENTER_VERTICAL
            minimumHeight = dp(70)
            setPadding(if (rtl) dp(8) else dp(14), dp(10), if (rtl) dp(14) else dp(8), dp(10))
            background = rippleRounded(colors.surface, dp(12).toFloat(), strokeColor = colors.surfaceBorder)
            setOnClickListener { openAction() }
        }
        val iconView = ImageView(this).apply {
            val bitmap = iconFile?.let { runCatching { BitmapFactory.decodeFile(it.absolutePath) }.getOrNull() }
            when {
                iconDrawable != null -> setImageDrawable(iconDrawable)
                bitmap != null -> setImageBitmap(bitmap)
                else -> setImageResource(iconRes)
            }
            scaleType = ImageView.ScaleType.FIT_CENTER
        }
        val textStack = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            applyCurrentLayoutDirection(this)
            TextView(context).apply {
                text = title
                textSize = 17f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(colors.ink)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.MIDDLE
                applyTextDirection(this)
                gravity = Gravity.START
                addView(this, LinearLayout.LayoutParams(-1, -2))
            }
            TextView(context).apply {
                text = subtitle
                textSize = 13f
                setTextColor(colors.textSecondary)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                applyTextDirection(this)
                gravity = Gravity.START
                addView(this, LinearLayout.LayoutParams(-1, -2).apply { topMargin = dp(3) })
            }
        }
        val trailingView: View? = if (showsChevron) {
            chevronIconView()
        } else {
            statusText?.let {
            TextView(this).apply {
                text = statusText
                textSize = 13f
                setTextColor(colors.textSecondary)
                gravity = Gravity.CENTER
            }
            }
        }
        if (rtl) {
            trailingView?.let { root.addView(it, trailingLayoutParams(showsChevron)) }
            root.addView(textStack, LinearLayout.LayoutParams(0, -2, 1f))
            root.addView(iconView, LinearLayout.LayoutParams(dp(34), dp(34)).apply { leftMargin = dp(12) })
        } else {
            root.addView(iconView, LinearLayout.LayoutParams(dp(34), dp(34)).apply { rightMargin = dp(12) })
            root.addView(textStack, LinearLayout.LayoutParams(0, -2, 1f))
            trailingView?.let { root.addView(it, trailingLayoutParams(showsChevron)) }
        }
        outer.addView(root, FrameLayout.LayoutParams(-1, -2))
        return outer
    }

    private fun iconButton(iconRes: Int, description: String, onClick: View.() -> Unit): ImageButton {
        return ImageButton(this).apply {
            setImageResource(iconRes)
            layoutDirection = if (isRightToLeftLayout()) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
            setColorFilter(colors.deepWater)
            background = rippleRounded(Color.TRANSPARENT, dp(22).toFloat())
            contentDescription = description
            scaleType = ImageView.ScaleType.CENTER
            setPadding(dp(10), dp(10), dp(10), dp(10))
            setOnClickListener { onClick() }
            layoutParams = LinearLayout.LayoutParams(dp(44), dp(44))
        }
    }

    private fun chevronIconView(): ImageView {
        return ImageView(this).apply {
            setImageResource(if (isRightToLeftLayout()) R.drawable.ic_chevron_left_24 else R.drawable.ic_chevron_right_24)
            imageTintList = ColorStateList.valueOf(colors.textSecondary)
            scaleType = ImageView.ScaleType.CENTER
            layoutDirection = View.LAYOUT_DIRECTION_LTR
            contentDescription = null
        }
    }

    private fun trailingLayoutParams(isChevron: Boolean): LinearLayout.LayoutParams {
        return if (isChevron) {
            LinearLayout.LayoutParams(dp(34), -1)
        } else {
            LinearLayout.LayoutParams(-2, -1)
        }
    }

    private fun pageBackground(): GradientDrawable {
        return GradientDrawable(
            GradientDrawable.Orientation.TOP_BOTTOM,
            intArrayOf(colors.pageTop, colors.pageMiddle, colors.pageBottom)
        )
    }

    private fun surfaceCardDrawable(): GradientDrawable {
        return roundedDrawable(colors.surface, dp(18).toFloat(), strokeColor = colors.surfaceBorder)
    }

    private fun roundedDrawable(
        color: Int,
        radius: Float = 0f,
        strokeColor: Int? = null,
        topLeft: Float? = null,
        topRight: Float? = null
    ): GradientDrawable {
        return GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            setColor(color)
            if (topLeft != null || topRight != null) {
                cornerRadii = floatArrayOf(
                    dp((topLeft ?: 0f).toInt()).toFloat(), dp((topLeft ?: 0f).toInt()).toFloat(),
                    dp((topRight ?: 0f).toInt()).toFloat(), dp((topRight ?: 0f).toInt()).toFloat(),
                    0f, 0f,
                    0f, 0f
                )
            } else {
                cornerRadius = radius
            }
            strokeColor?.let { setStroke(dp(1), it) }
        }
    }

    private fun rippleRounded(color: Int, radius: Float, strokeColor: Int? = null): RippleDrawable {
        return RippleDrawable(
            ColorStateList.valueOf(colors.ripple),
            roundedDrawable(color, radius, strokeColor),
            roundedDrawable(Color.WHITE, radius)
        )
    }

    private fun configureSystemBars(mode: SurfaceMode) {
        val isLandscapeViewer = mode == SurfaceMode.Viewer &&
            resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        window.statusBarColor = when (mode) {
            SurfaceMode.Shell -> colors.pageTop
            SurfaceMode.Viewer -> if (isLandscapeViewer) Color.TRANSPARENT else colors.pageTop
        }
        window.navigationBarColor = when (mode) {
            SurfaceMode.Shell -> colors.pageBottom
            SurfaceMode.Viewer -> if (isLandscapeViewer) Color.TRANSPARENT else colors.pageBottom
        }
        val lightSystemBars = !colors.isDark
        val flags = when (mode) {
            SurfaceMode.Shell -> lightSystemBarsFlag(lightSystemBars)
            SurfaceMode.Viewer -> if (isLandscapeViewer) {
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    lightSystemBarsFlag(lightSystemBars)
            } else {
                lightSystemBarsFlag(lightSystemBars)
            }
        }
        window.decorView.systemUiVisibility = flags
        if (Build.VERSION.SDK_INT >= 30) {
            val appearance = if (lightSystemBars) {
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                    WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            } else {
                0
            }
            window.decorView.windowInsetsController?.setSystemBarsAppearance(
                appearance,
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                    WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            )
        }
    }

    private fun lightSystemBarsFlag(enabled: Boolean): Int {
        if (!enabled) return 0
        return View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or
            (if (Build.VERSION.SDK_INT >= 26) View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR else 0)
    }

    private fun listSubtitle(page: WebPage): String {
        val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(page.createdAt))
        val fileName = page.sourceFileName
        return if (fileName.isNullOrBlank()) date else "$date · $fileName"
    }

    private fun deletedSubtitle(deletedPage: DeletedWebPage): String {
        val date = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(deletedPage.deletedAt))
        val fileName = deletedPage.page.sourceFileName
        return if (fileName.isNullOrBlank()) date else "$date · $fileName"
    }

    private fun recentlyDeletedItems(): List<RecentlyDeletedListItem> {
        val items = mutableListOf<RecentlyDeletedListItem>()
        var currentGroup: String? = null
        for (deletedPage in library.recentlyDeletedPages) {
            val group = deletedGroupTitle(deletedPage.deletedAt)
            if (group != currentGroup) {
                items.add(RecentlyDeletedListItem.Header(group))
                currentGroup = group
            }
            items.add(RecentlyDeletedListItem.Item(deletedPage))
        }
        return items
    }

    private fun deletedGroupTitle(timestamp: Long): String {
        val now = Calendar.getInstance()
        val target = Calendar.getInstance().apply { timeInMillis = timestamp }
        if (now.get(Calendar.YEAR) == target.get(Calendar.YEAR) &&
            now.get(Calendar.DAY_OF_YEAR) == target.get(Calendar.DAY_OF_YEAR)
        ) {
            return appString(R.string.today)
        }
        val diffMillis = now.timeInMillis - timestamp
        val sevenDays = 7L * 24L * 60L * 60L * 1000L
        if (diffMillis <= sevenDays) return appString(R.string.within_week)
        val oneMonthAgo = Calendar.getInstance().apply { add(Calendar.MONTH, -1) }
        if (target.after(oneMonthAgo)) return appString(R.string.within_month)
        return appString(R.string.earlier)
    }

    private fun appString(resId: Int): String {
        return AppPreferences.localizedContext(this).getString(resId)
    }

    private fun isRightToLeftLayout(): Boolean {
        return AppPreferences.isRightToLeft(this)
    }

    private fun applyCurrentLayoutDirection(view: View) {
        val direction = if (isRightToLeftLayout()) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
        view.layoutDirection = direction
        view.textDirection = if (direction == View.LAYOUT_DIRECTION_RTL) {
            View.TEXT_DIRECTION_RTL
        } else {
            View.TEXT_DIRECTION_LTR
        }
    }

    private fun applyTextDirection(textView: TextView) {
        textView.layoutDirection = if (isRightToLeftLayout()) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
        textView.textDirection = if (isRightToLeftLayout()) {
            View.TEXT_DIRECTION_LOCALE
        } else {
            View.TEXT_DIRECTION_LTR
        }
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun viewerTopChromeHeight(): Int {
        return dp(54)
    }

    private inner class PageRecyclerAdapter(
        private val items: List<WebPage>,
        private val onOpen: (WebPage) -> Unit
    ) : RecyclerView.Adapter<PageRecyclerAdapter.PageViewHolder>() {
        override fun getItemCount(): Int = items.size

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): PageViewHolder {
            return PageViewHolder(FrameLayout(parent.context).apply {
                layoutParams = RecyclerView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.WRAP_CONTENT
                )
            })
        }

        override fun onBindViewHolder(holder: PageViewHolder, position: Int) {
            val page = items[position]
            holder.bind(row(
                iconRes = if (page.resolvedEntries().size > 1) R.drawable.ic_folder_fill_24 else R.drawable.ic_doc_text_fill_24,
                iconDrawable = projectIconDrawable(page, library.projectIconFileFor(page), colors.surface),
                title = page.title,
                subtitle = listSubtitle(page),
                statusText = statusText(page.lastLoadStatus).takeIf { page.lastLoadStatus != WebPageLoadStatus.READY },
                showsChevron = false,
                openAction = { onOpen(page) }
            ))
        }

        fun pageAt(position: Int): WebPage? = items.getOrNull(position)

        inner class PageViewHolder(container: FrameLayout) : RecyclerView.ViewHolder(container) {
            fun bind(view: View) {
                val container = itemView as FrameLayout
                container.removeAllViews()
                container.addView(view, FrameLayout.LayoutParams(-1, -2))
            }
        }
    }

    private inner class ProjectSwipeDeleteCallback(
        private val pageAdapter: PageRecyclerAdapter,
        swipeDirections: Int
    ) : ItemTouchHelper.SimpleCallback(0, swipeDirections) {
        private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = ACCENT_CORAL
        }

        override fun onMove(
            recyclerView: RecyclerView,
            viewHolder: RecyclerView.ViewHolder,
            target: RecyclerView.ViewHolder
        ): Boolean = false

        override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
            val position = viewHolder.bindingAdapterPosition
            val page = pageAdapter.pageAt(position)
            if (page == null) {
                pageAdapter.notifyItemChanged(position)
                return
            }

            library.delete(page)
            if (library.pages.isEmpty()) {
                showHome()
            } else {
                pageAdapter.notifyItemRemoved(position)
            }
        }

        override fun onChildDraw(
            c: Canvas,
            recyclerView: RecyclerView,
            viewHolder: RecyclerView.ViewHolder,
            dX: Float,
            dY: Float,
            actionState: Int,
            isCurrentlyActive: Boolean
        ) {
            val rtl = isRightToLeftLayout()
            val isDeleteSwipe = if (rtl) dX > 0f else dX < 0f
            if (actionState == ItemTouchHelper.ACTION_STATE_SWIPE && isDeleteSwipe) {
                drawDeleteBackground(c, viewHolder.itemView, dX, rtl)
            }
            super.onChildDraw(c, recyclerView, viewHolder, dX, dY, actionState, isCurrentlyActive)
        }

        private fun drawDeleteBackground(canvas: Canvas, itemView: View, dX: Float, rtl: Boolean) {
            val top = itemView.top + dp(6)
            val bottom = itemView.bottom - dp(6)
            val left: Int
            val right: Int
            if (rtl) {
                left = itemView.left + dp(16)
                right = itemView.left + dX.toInt()
                if (right <= left) return
            } else {
                left = itemView.right + dX.toInt()
                right = itemView.right - dp(16)
                if (left >= right) return
            }
            canvas.drawRoundRect(
                left.toFloat(),
                top.toFloat(),
                right.toFloat(),
                bottom.toFloat(),
                dp(12).toFloat(),
                dp(12).toFloat(),
                backgroundPaint
            )

            val icon = getDrawable(R.drawable.ic_delete_24) ?: return
            icon.setTint(ACTION_CORAL_LABEL)
            val iconSize = dp(24)
            val iconMargin = dp(28)
            val iconLeft = if (rtl) left + iconMargin else right - iconMargin - iconSize
            val iconTop = top + (bottom - top - iconSize) / 2
            icon.bounds = Rect(iconLeft, iconTop, iconLeft + iconSize, iconTop + iconSize)
            icon.draw(canvas)
        }
    }

    private sealed class RecentlyDeletedListItem {
        data class Header(val title: String) : RecentlyDeletedListItem()
        data class Item(val deletedPage: DeletedWebPage) : RecentlyDeletedListItem()
    }

    private inner class RecentlyDeletedAdapter(
        private val items: List<RecentlyDeletedListItem>,
        private val onOpen: (DeletedWebPage) -> Unit
    ) : RecyclerView.Adapter<RecyclerView.ViewHolder>() {
        override fun getItemCount(): Int = items.size
        override fun getItemViewType(position: Int): Int {
            return when (items[position]) {
                is RecentlyDeletedListItem.Header -> 0
                is RecentlyDeletedListItem.Item -> 1
            }
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
            return if (viewType == 0) {
                HeaderViewHolder(TextView(parent.context).apply {
                    layoutParams = RecyclerView.LayoutParams(-1, -2)
                })
            } else {
                DeletedPageViewHolder(FrameLayout(parent.context).apply {
                    layoutParams = RecyclerView.LayoutParams(-1, -2)
                })
            }
        }

        override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
            when (val item = items[position]) {
                is RecentlyDeletedListItem.Header -> (holder as HeaderViewHolder).bind(item.title)
                is RecentlyDeletedListItem.Item -> (holder as DeletedPageViewHolder).bind(item.deletedPage)
            }
        }

        fun deletedPageAt(position: Int): DeletedWebPage? {
            return (items.getOrNull(position) as? RecentlyDeletedListItem.Item)?.deletedPage
        }

        inner class HeaderViewHolder(private val textView: TextView) : RecyclerView.ViewHolder(textView) {
            fun bind(title: String) {
                textView.text = title
                textView.textSize = 13f
                textView.typeface = Typeface.DEFAULT_BOLD
                textView.setTextColor(colors.textSecondary)
                textView.includeFontPadding = false
                textView.gravity = Gravity.START
                textView.setPaddingRelative(dp(24), dp(18), dp(24), dp(8))
            }
        }

        inner class DeletedPageViewHolder(container: FrameLayout) : RecyclerView.ViewHolder(container) {
            fun bind(deletedPage: DeletedWebPage) {
                val container = itemView as FrameLayout
                container.removeAllViews()
                container.addView(row(
                    iconRes = if (deletedPage.page.resolvedEntries().size > 1) R.drawable.ic_folder_fill_24 else R.drawable.ic_doc_text_fill_24,
                    iconDrawable = projectIconDrawable(deletedPage, library.projectIconFileFor(deletedPage), colors.surface),
                    title = deletedPage.page.title,
                    subtitle = deletedSubtitle(deletedPage),
                    statusText = statusText(deletedPage.page.lastLoadStatus).takeIf {
                        deletedPage.page.lastLoadStatus != WebPageLoadStatus.READY
                    },
                    showsChevron = false,
                    openAction = { onOpen(deletedPage) }
                ), FrameLayout.LayoutParams(-1, -2))
            }
        }
    }

    private inner class RecentlyDeletedSwipeCallback(
        private val adapter: RecentlyDeletedAdapter
    ) : ItemTouchHelper.SimpleCallback(0, ItemTouchHelper.LEFT or ItemTouchHelper.RIGHT) {
        private val restorePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ACCENT_LEAF }
        private val deletePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = ACCENT_CORAL }

        override fun onMove(
            recyclerView: RecyclerView,
            viewHolder: RecyclerView.ViewHolder,
            target: RecyclerView.ViewHolder
        ): Boolean = false

        override fun getSwipeDirs(recyclerView: RecyclerView, viewHolder: RecyclerView.ViewHolder): Int {
            return if (adapter.deletedPageAt(viewHolder.bindingAdapterPosition) == null) 0 else super.getSwipeDirs(recyclerView, viewHolder)
        }

        override fun onSwiped(viewHolder: RecyclerView.ViewHolder, direction: Int) {
            val position = viewHolder.bindingAdapterPosition
            val deletedPage = adapter.deletedPageAt(position)
            if (deletedPage == null) {
                adapter.notifyItemChanged(position)
                return
            }
            val rtl = isRightToLeftLayout()
            val isRestore = if (rtl) direction == ItemTouchHelper.LEFT else direction == ItemTouchHelper.RIGHT
            if (isRestore) {
                restoreDeletedPage(deletedPage)
            } else {
                adapter.notifyItemChanged(position)
                confirmPermanentlyDelete(deletedPage)
            }
        }

        override fun onChildDraw(
            c: Canvas,
            recyclerView: RecyclerView,
            viewHolder: RecyclerView.ViewHolder,
            dX: Float,
            dY: Float,
            actionState: Int,
            isCurrentlyActive: Boolean
        ) {
            if (actionState == ItemTouchHelper.ACTION_STATE_SWIPE &&
                adapter.deletedPageAt(viewHolder.bindingAdapterPosition) != null
            ) {
                val rtl = isRightToLeftLayout()
                val restoreSwipe = if (rtl) dX < 0f else dX > 0f
                drawRecentDeleteAction(c, viewHolder.itemView, dX, restoreSwipe, rtl)
            }
            super.onChildDraw(c, recyclerView, viewHolder, dX, dY, actionState, isCurrentlyActive)
        }

        private fun drawRecentDeleteAction(
            canvas: Canvas,
            itemView: View,
            dX: Float,
            restoreSwipe: Boolean,
            rtl: Boolean
        ) {
            val top = itemView.top + dp(6)
            val bottom = itemView.bottom - dp(6)
            val swipingRight = dX > 0f
            val left: Int
            val right: Int
            if (swipingRight) {
                left = itemView.left + dp(16)
                right = itemView.left + dX.toInt()
                if (right <= left) return
            } else {
                left = itemView.right + dX.toInt()
                right = itemView.right - dp(16)
                if (left >= right) return
            }
            canvas.drawRoundRect(
                left.toFloat(),
                top.toFloat(),
                right.toFloat(),
                bottom.toFloat(),
                dp(12).toFloat(),
                dp(12).toFloat(),
                if (restoreSwipe) restorePaint else deletePaint
            )

            val icon = getDrawable(if (restoreSwipe) R.drawable.ic_refresh_24 else R.drawable.ic_delete_24) ?: return
            icon.setTint(if (restoreSwipe) ACTION_LEAF_LABEL else ACTION_CORAL_LABEL)
            val iconSize = dp(24)
            val iconMargin = dp(28)
            val iconLeft = if (swipingRight) left + iconMargin else right - iconMargin - iconSize
            val iconTop = top + (bottom - top - iconSize) / 2
            icon.bounds = Rect(iconLeft, iconTop, iconLeft + iconSize, iconTop + iconSize)
            icon.draw(canvas)
        }
    }

    private inner class SelectionAdapter<T>(
        private val items: List<T>,
        private val selectedRawValue: String,
        private val rawValueFor: (T) -> String,
        private val titleFor: (T) -> String,
        private val onSelect: (T) -> Unit
    ) : BaseAdapter() {
        override fun getCount(): Int = items.size
        override fun getItem(position: Int): T = items[position]
        override fun getItemId(position: Int): Long = position.toLong()

        override fun getView(position: Int, convertView: View?, parent: ViewGroup?): View {
            val item = getItem(position)
            val selected = rawValueFor(item) == selectedRawValue
            val rtl = isRightToLeftLayout()
            val outer = FrameLayout(this@MainActivity).apply {
                setPadding(dp(16), dp(5), dp(16), dp(5))
            }
            val root = LinearLayout(this@MainActivity).apply {
                orientation = LinearLayout.HORIZONTAL
                layoutDirection = View.LAYOUT_DIRECTION_LTR
                gravity = Gravity.CENTER_VERTICAL
                minimumHeight = dp(58)
                setPadding(dp(16), dp(10), dp(16), dp(10))
                background = rippleRounded(colors.surface, dp(12).toFloat(), strokeColor = colors.surfaceBorder)
                setOnClickListener { onSelect(item) }
            }
            val titleView = TextView(this@MainActivity).apply {
                text = titleFor(item)
                textSize = 17f
                setTextColor(colors.ink)
                maxLines = 1
                ellipsize = TextUtils.TruncateAt.END
                applyTextDirection(this)
                gravity = Gravity.CENTER_VERTICAL or Gravity.START
            }
            val checkView = if (selected) {
                ImageView(this@MainActivity).apply {
                    setImageResource(R.drawable.ic_check_24)
                    imageTintList = ColorStateList.valueOf(colors.deepWater)
                    scaleType = ImageView.ScaleType.CENTER
                    layoutDirection = View.LAYOUT_DIRECTION_LTR
                }
            } else {
                null
            }
            if (selected) {
                if (rtl) {
                    root.addView(checkView, LinearLayout.LayoutParams(dp(24), dp(24)).apply { rightMargin = dp(12) })
                    root.addView(titleView, LinearLayout.LayoutParams(0, -2, 1f))
                } else {
                    root.addView(titleView, LinearLayout.LayoutParams(0, -2, 1f))
                    root.addView(checkView, LinearLayout.LayoutParams(dp(24), dp(24)).apply { leftMargin = dp(12) })
                }
            } else {
                root.addView(titleView, LinearLayout.LayoutParams(0, -2, 1f))
            }
            outer.addView(root, FrameLayout.LayoutParams(-1, -2))
            return outer
        }
    }

    private inner class RuntimeStorageBridge(private val projectFolder: File) {
        @JavascriptInterface
        fun saveLocalStorage(rawItems: String) {
            val json = runCatching { JSONObject(rawItems) }.getOrNull() ?: return
            val items = json.keys().asSequence().associateWith { key -> json.optString(key, "") }
            WebPageRuntimeStorage.saveLocalStorageItems(projectFolder, items)
        }
    }

    private class ProjectWebViewLoader(
        private val page: WebPage,
        private val projectFolder: File
    ) {
        fun responseFor(url: Uri): WebResourceResponse? {
            val relativePath = relativePathFor(page, url) ?: return null
            val safePath = runCatching { ZipTools.safeRelativePath(relativePath) }.getOrNull()
                ?: return errorResponse(400, "Bad Request")
            if (safePath == WebPageLibrary.archiveFallbackEntryRelativePath) {
                return WebResourceResponse(
                    "text/html",
                    "UTF-8",
                    ByteArrayInputStream(injectRuntimeStorageScript(WebPageLibrary.bundledArchiveFallbackTemplateHTML).toByteArray(Charsets.UTF_8))
                )
            }
            val file = File(projectFolder, safePath)
            if (!ZipTools.isDescendant(file, projectFolder) || !file.isFile) {
                return errorResponse(404, "Not Found")
            }

            val extension = file.extension.lowercase()
            val mimeType = mimeTypeFor(extension)
            return if (WebPageLibrary.isSupportedHTML(file.name.lowercase())) {
                val html = runCatching { file.readText(Charsets.UTF_8) }.getOrNull()
                    ?: return errorResponse(500, "Unable to Read File")
                WebResourceResponse(
                    mimeType,
                    "UTF-8",
                    ByteArrayInputStream(injectRuntimeStorageScript(html).toByteArray(Charsets.UTF_8))
                )
            } else {
                WebResourceResponse(mimeType, null, FileInputStream(file))
            }
        }

        private fun injectRuntimeStorageScript(html: String): String {
            val script = "<script>${runtimeStorageScript(projectFolder)}</script>"
            val doctypeMatch = Regex("^\\s*<!doctype[^>]*>", RegexOption.IGNORE_CASE).find(html)
            if (doctypeMatch != null) {
                val insertIndex = doctypeMatch.range.last + 1
                return html.substring(0, insertIndex) + script + html.substring(insertIndex)
            }
            return script + html
        }

        private fun runtimeStorageScript(projectFolder: File): String {
            val items = JSONObject()
            WebPageRuntimeStorage.localStorageItems(projectFolder)
                .toSortedMap()
                .forEach { (key, value) -> items.put(key, value) }
            val hasSnapshot = File(projectFolder, WebPageRuntimeStorage.localStorageRelativePath).exists()
            val itemsJSON = items.toString()
                .replace("</", "<\\/")
                .replace("\u2028", "\\u2028")
                .replace("\u2029", "\\u2029")
            return """
                (function() {
                  if (window.__htmlAnywhereRuntimeStorageInstalled) { return; }
                  window.__htmlAnywhereRuntimeStorageInstalled = true;
                  var bootstrapItems = $itemsJSON;
                  var hasSnapshot = $hasSnapshot;

                  function restoreSnapshot() {
                    try {
                      if (!hasSnapshot) { return; }
                      localStorage.clear();
                      Object.keys(bootstrapItems).forEach(function(key) {
                        localStorage.setItem(key, String(bootstrapItems[key]));
                      });
                    } catch (error) {}
                  }

                  function capture() {
                    try {
                      var items = {};
                      for (var index = 0; index < localStorage.length; index += 1) {
                        var key = localStorage.key(index);
                        if (key !== null) {
                          items[key] = localStorage.getItem(key) || "";
                        }
                      }
                      if (window.$RUNTIME_BRIDGE_NAME && window.$RUNTIME_BRIDGE_NAME.saveLocalStorage) {
                        window.$RUNTIME_BRIDGE_NAME.saveLocalStorage(JSON.stringify(items));
                      }
                    } catch (error) {}
                  }

                  function scheduleCapture() {
                    setTimeout(capture, 0);
                  }

                  restoreSnapshot();
                  window.__htmlAnywhereCaptureLocalStorage = capture;

                  var originalSetItem = Storage.prototype.setItem;
                  var originalRemoveItem = Storage.prototype.removeItem;
                  var originalClear = Storage.prototype.clear;
                  Storage.prototype.setItem = function(key, value) {
                    var result = originalSetItem.apply(this, arguments);
                    if (this === window.localStorage) { scheduleCapture(); }
                    return result;
                  };
                  Storage.prototype.removeItem = function(key) {
                    var result = originalRemoveItem.apply(this, arguments);
                    if (this === window.localStorage) { scheduleCapture(); }
                    return result;
                  };
                  Storage.prototype.clear = function() {
                    var result = originalClear.apply(this, arguments);
                    if (this === window.localStorage) { scheduleCapture(); }
                    return result;
                  };
                  window.addEventListener("pagehide", capture);
                  window.addEventListener("beforeunload", capture);
                  document.addEventListener("visibilitychange", function() {
                    if (document.visibilityState === "hidden") { capture(); }
                  });
                  scheduleCapture();
                })();
            """.trimIndent()
        }

        private fun mimeTypeFor(extension: String): String {
            return when (extension) {
                "html", "htm" -> "text/html"
                "js" -> "text/javascript"
                "css" -> "text/css"
                "svg" -> "image/svg+xml"
                else -> MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "application/octet-stream"
            }
        }

        private fun errorResponse(statusCode: Int, reason: String): WebResourceResponse {
            return WebResourceResponse(
                "text/plain",
                "UTF-8",
                statusCode,
                reason,
                mapOf("Cache-Control" to "no-store"),
                ByteArrayInputStream(ByteArray(0))
            )
        }

        companion object {
            private const val HOST_SUFFIX = ".htmlanywhere.local"

            fun originFor(page: WebPage): String {
                return "https://${page.id.lowercase()}$HOST_SUFFIX"
            }

            fun urlFor(page: WebPage, relativePath: String): Uri {
                val builder = Uri.parse(originFor(page)).buildUpon()
                relativePath.split('/').filter { it.isNotBlank() }.forEach { segment ->
                    builder.appendPath(segment)
                }
                return builder.build()
            }

            fun isProjectUrl(page: WebPage, url: Uri): Boolean {
                return url.scheme == "https" && url.host == "${page.id.lowercase()}$HOST_SUFFIX"
            }

            fun relativePathFor(page: WebPage, url: Uri): String? {
                if (!isProjectUrl(page, url)) return null
                return url.path?.removePrefix("/")?.ifBlank { null }
            }
        }
    }

    private data class NativeFileGroup(
        val directoryPath: String,
        val files: List<WebPageProjectFile>
    ) {
        val title: String?
            get() = directoryPath.ifBlank { null }
    }

    private enum class NativeFileKind {
        IMAGE,
        VIDEO,
        AUDIO,
        PDF,
        TEXT,
        DOCUMENT,
        OTHER
    }

    private enum class SurfaceMode { Shell, Viewer }

    private data class AppPalette(
        val isDark: Boolean,
        val pageTop: Int,
        val pageMiddle: Int,
        val pageBottom: Int,
        val surface: Int,
        val surfaceInset: Int,
        val surfaceDock: Int,
        val surfaceBorder: Int,
        val ink: Int,
        val textSecondary: Int,
        val deepWater: Int,
        val ripple: Int
    ) {
        companion object {
            fun forContext(context: Context): AppPalette {
                val preference = AppPreferences.selectedAppearance(context).rawValue
                val systemDark = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
                    Configuration.UI_MODE_NIGHT_YES
                val dark = when (preference) {
                    "light" -> false
                    "dark" -> true
                    else -> systemDark
                }
                return if (dark) {
                    AppPalette(
                        isDark = true,
                        pageTop = 0xFF172033.toInt(),
                        pageMiddle = 0xFF202A3A.toInt(),
                        pageBottom = 0xFF121821.toInt(),
                        surface = 0xFF253044.toInt(),
                        surfaceInset = 0xFF1C2637.toInt(),
                        surfaceDock = 0xFF20283A.toInt(),
                        surfaceBorder = 0xFF344052.toInt(),
                        ink = 0xFFD4D9DC.toInt(),
                        textSecondary = 0xFFA8B3BF.toInt(),
                        deepWater = 0xFFB9C5FF.toInt(),
                        ripple = 0x33B9C5FF
                    )
                } else {
                    AppPalette(
                        isDark = false,
                        pageTop = 0xFFDDE7FB.toInt(),
                        pageMiddle = 0xFFEEF3FA.toInt(),
                        pageBottom = 0xFFF6F9FC.toInt(),
                        surface = 0xFFFFFFFF.toInt(),
                        surfaceInset = 0xFFF3F3FB.toInt(),
                        surfaceDock = 0xFFEBEDF9.toInt(),
                        surfaceBorder = 0xFFF2F4FA.toInt(),
                        ink = 0xFF43536C.toInt(),
                        textSecondary = 0xFF7B8997.toInt(),
                        deepWater = 0xFF556397.toInt(),
                        ripple = 0x22556397
                    )
                }
            }
        }
    }

    private sealed class Screen {
        object Home : Screen()
        object RecentlyDeleted : Screen()
        object Settings : Screen()
        object SettingsHomeLayout : Screen()
        object SettingsLanguage : Screen()
        object SettingsAppearance : Screen()
        data class Viewer(
            val pageID: String,
            val entryID: String,
            val webView: WebView,
            val toolbar: LinearLayout
        ) : Screen()
        data class DeletedViewer(
            val deletedPageID: String,
            val entryID: String,
            val webView: WebView,
            val toolbar: LinearLayout
        ) : Screen()
        data class NativeFileViewer(val pageID: String) : Screen()
        data class DeletedNativeFileViewer(val deletedPageID: String) : Screen()
    }

    private companion object {
        const val PAGE_TOP = 0xFFDDE7FB.toInt()
        const val PAGE_MIDDLE = 0xFFEEF3FA.toInt()
        const val PAGE_BOTTOM = 0xFFF6F9FC.toInt()
        const val SURFACE = 0xFFFFFFFF.toInt()
        const val SURFACE_INSET = 0xFFF3F3FB.toInt()
        const val SURFACE_DOCK = 0xFFEBEDF9.toInt()
        const val SURFACE_BORDER = 0xFFF2F4FA.toInt()
        const val INK = 0xFF43536C.toInt()
        const val TEXT_SECONDARY = 0xFF7B8997.toInt()
        const val DEEP_WATER = 0xFF556397.toInt()
        const val ACCENT_SKY = 0xFF4CC8FF.toInt()
        const val ACCENT_CORAL = 0xFFFF5553.toInt()
        const val ACCENT_LEAF = 0xFF61D394.toInt()
        const val ACCENT_AI_PURPLE = 0xFFC47EFF.toInt()
        const val ACCENT_MINT = 0xFF03D1B2.toInt()
        const val ACTION_BLUE_LABEL = 0xFF0073CC.toInt()
        const val ACTION_CORAL_LABEL = 0xFFAF0036.toInt()
        const val ACTION_LEAF_LABEL = 0xFF096B3B.toInt()
        const val RIPPLE = 0x22556397
        const val SKY_TOP_GLOW_START = 0x8700F0FF.toInt()
        const val SKY_TOP_GLOW_END = 0x0000F0FF
        const val SKY_INNER_SHADOW = 0xFF499DF1.toInt()
        const val ACTION_DROP_SHADOW = 0x1A000000
        const val VIEWER_FLOATING_CONTROL = 0x6BFFFFFF
        const val VIEWER_FLOATING_CONTROL_STROKE = 0x40F2F4FA
        const val RUNTIME_BRIDGE_NAME = "HTMLKeepRuntimeStorage"
        const val APP_PRODUCT_URL = "https://apps.apple.com/app/id6767142789"
        const val APP_REVIEW_URL = "https://apps.apple.com/app/id6767142789?action=write-review"
        const val GITHUB_REPOSITORY_URL = "https://github.com/UXplayer/HTML-Keep"
        const val DISCORD_URL = "https://discord.gg/MTE3ER26X"
    }

    private class EmptyStateBubbleView(
        context: Context,
        private val fillColor: Int,
        private val strokeColor: Int
    ) : LinearLayout(context) {
        private val density = context.resources.displayMetrics.density
        private val pointerWidth = 24f * density
        private val pointerHeight = 18f * density
        private val pointerOverlap = 1f * density
        private val cornerRadius = 20f * density
        private val shadowOffset = 2f * density
        private val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = fillColor
        }
        private val shadowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.FILL
            color = Color.argb(13, 0, 0, 0)
        }
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeWidth = 1.5f
            color = strokeColor
        }
        private val pointerPath = Path()

        init {
            orientation = VERTICAL
            setWillNotDraw(false)
            setPadding((16f * density).toInt(), (pointerHeight + 16f * density).toInt(), (16f * density).toInt(), (19f * density).toInt())
            clipToPadding = false
        }

        fun setContent(title: String, message: String, titleColor: Int, messageColor: Int) {
            removeAllViews()
            TextView(context).apply {
                text = title
                textSize = 20f
                typeface = Typeface.DEFAULT_BOLD
                setTextColor(titleColor)
                gravity = Gravity.CENTER
                maxLines = 2
                ellipsize = TextUtils.TruncateAt.END
                includeFontPadding = false
                addView(this, LayoutParams(-1, -2))
            }
            TextView(context).apply {
                text = message
                textSize = 16f
                setTextColor(messageColor)
                setLineSpacing(0f, 1.25f)
                gravity = Gravity.CENTER
                includeFontPadding = true
                addView(this, LayoutParams(-1, -2).apply { topMargin = (8f * density).toInt() })
            }
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val bubbleTop = pointerHeight - pointerOverlap
            val bubbleRect = RectF(0f, bubbleTop, width.toFloat(), height.toFloat() - shadowOffset)
            val pointerLeft = width / 2f - pointerWidth / 2f
            val pointerRight = width / 2f + pointerWidth / 2f
            val pointerBottom = pointerHeight + pointerOverlap

            pointerPath.reset()
            pointerPath.moveTo(pointerLeft, pointerBottom)
            pointerPath.lineTo(width / 2f, 0f)
            pointerPath.lineTo(pointerRight, pointerBottom)
            pointerPath.close()

            canvas.save()
            canvas.translate(0f, shadowOffset)
            canvas.drawRoundRect(bubbleRect, cornerRadius, cornerRadius, shadowPaint)
            canvas.drawPath(pointerPath, shadowPaint)
            canvas.restore()

            canvas.drawRoundRect(bubbleRect, cornerRadius, cornerRadius, fillPaint)
            canvas.drawPath(pointerPath, fillPaint)

            canvas.drawRoundRect(bubbleRect, cornerRadius, cornerRadius, strokePaint)
            canvas.drawRect(pointerLeft - strokePaint.strokeWidth, bubbleTop - strokePaint.strokeWidth, pointerRight + strokePaint.strokeWidth, bubbleTop + strokePaint.strokeWidth * 2, fillPaint)

            pointerPath.reset()
            pointerPath.moveTo(pointerLeft, pointerBottom)
            pointerPath.lineTo(width / 2f, 0f)
            pointerPath.lineTo(pointerRight, pointerBottom)
            canvas.drawPath(pointerPath, strokePaint)
        }
    }

    private class KeyedVideoIllustrationView(
        context: Context,
        private val fallbackIconRes: Int,
        private val fallbackTint: Int
    ) : View(context) {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private val fallbackDrawable = context.getDrawable(fallbackIconRes)?.mutate()?.apply {
            setTint(fallbackTint)
        }
        private val sprite: Bitmap? = loadSpriteSheet(context)
        private var frameIntervalMs: Long = 1000L / TARGET_FRAME_RATE
        private var loopStartMs = SystemClock.uptimeMillis()
        private var holdStartMs = 0L
        private var fadeStartMs = 0L
        private var loopState = LoopState.PLAYING

        override fun onAttachedToWindow() {
            super.onAttachedToWindow()
            loopStartMs = SystemClock.uptimeMillis()
            postInvalidateOnAnimation()
        }

        override fun onDraw(canvas: Canvas) {
            super.onDraw(canvas)
            val sheet = sprite
            if (sheet == null) {
                drawFallback(canvas)
                postInvalidateOnAnimation()
                return
            }
            drawAnimatedFrames(canvas, sheet)
            postInvalidateOnAnimation()
        }

        private fun drawAnimatedFrames(canvas: Canvas, sheet: Bitmap) {
            val now = SystemClock.uptimeMillis()
            val durationMs = (FRAME_COUNT * frameIntervalMs).coerceAtLeast(frameIntervalMs)
            when (loopState) {
                LoopState.PLAYING -> {
                    val elapsed = now - loopStartMs
                    if (elapsed >= durationMs) {
                        loopState = LoopState.HOLDING
                        holdStartMs = now
                        drawFrame(canvas, sheet, FRAME_COUNT - 1, 255)
                    } else {
                        val index = (elapsed / frameIntervalMs).toInt().coerceIn(0, FRAME_COUNT - 1)
                        drawFrame(canvas, sheet, index, 255)
                    }
                }
                LoopState.HOLDING -> {
                    drawFrame(canvas, sheet, FRAME_COUNT - 1, 255)
                    if (now - holdStartMs >= LOOP_HOLD_MS) {
                        loopState = LoopState.FADING
                        fadeStartMs = now
                    }
                }
                LoopState.FADING -> {
                    val progress = ((now - fadeStartMs).toFloat() / LOOP_FADE_MS).coerceIn(0f, 1f)
                    drawFrame(canvas, sheet, 0, 255)
                    drawFrame(canvas, sheet, FRAME_COUNT - 1, ((1f - progress) * 255).toInt())
                    if (progress >= 1f) {
                        loopState = LoopState.PLAYING
                        loopStartMs = now
                    }
                }
            }
        }

        private fun drawFrame(canvas: Canvas, sheet: Bitmap, index: Int, alpha: Int) {
            val sourceLeft = (index % SPRITE_COLUMNS) * FRAME_SIZE
            val sourceTop = (index / SPRITE_COLUMNS) * FRAME_SIZE
            val sourceRect = Rect(
                sourceLeft + FRAME_EDGE_CROP,
                sourceTop + FRAME_EDGE_CROP,
                sourceLeft + FRAME_SIZE - FRAME_EDGE_CROP,
                sourceTop + FRAME_SIZE - FRAME_EDGE_CROP
            )
            val rect = fitCenterRect(FRAME_SIZE, FRAME_SIZE)
            paint.alpha = alpha
            canvas.drawBitmap(sheet, sourceRect, rect, paint)
            paint.alpha = 255
        }

        private fun drawFallback(canvas: Canvas) {
            val drawable = fallbackDrawable ?: return
            val size = (minOf(width, height) * 0.6f).toInt()
            val left = (width - size) / 2
            val top = (height - size) / 2
            drawable.bounds = Rect(left, top, left + size, top + size)
            drawable.draw(canvas)
        }

        private fun fitCenterRect(sourceWidth: Int, sourceHeight: Int): Rect {
            if (width <= 0 || height <= 0 || sourceWidth <= 0 || sourceHeight <= 0) return Rect(0, 0, width, height)
            val scale = minOf(width.toFloat() / sourceWidth, height.toFloat() / sourceHeight)
            val targetWidth = (sourceWidth * scale).toInt()
            val targetHeight = (sourceHeight * scale).toInt()
            val left = (width - targetWidth) / 2
            val top = (height - targetHeight) / 2
            return Rect(left, top, left + targetWidth, top + targetHeight)
        }

        private enum class LoopState {
            PLAYING,
            HOLDING,
            FADING
        }

        companion object {
            private const val FRAME_SIZE = 240
            private const val FRAME_EDGE_CROP = 2
            private const val SPRITE_COLUMNS = 8
            private const val FRAME_COUNT = 61
            private const val TARGET_FRAME_RATE = 15
            private const val LOOP_HOLD_MS = 350L
            private const val LOOP_FADE_MS = 220L
            @Volatile private var cachedSprite: Bitmap? = null

            private fun loadSpriteSheet(context: Context): Bitmap? {
                cachedSprite?.let { return it }
                return synchronized(KeyedVideoIllustrationView::class.java) {
                    cachedSprite ?: BitmapFactory.decodeResource(context.resources, R.drawable.empty_state_bear_sheet)?.also {
                        it.setHasAlpha(true)
                        cachedSprite = it
                    }
                }
            }
        }
    }

    private class ProjectIconDrawable(
        private val bitmap: Bitmap?,
        private val glyph: Drawable?,
        private val topColor: Int?,
        private val bottomColor: Int?,
        private val fallbackBackground: Int,
        private val fallbackInk: Int,
        private val hostColor: Int
    ) : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        private val strokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
        }
        private val clipPath = Path()

        override fun draw(canvas: Canvas) {
            val rect = RectF(bounds)
            if (rect.width() <= 0f || rect.height() <= 0f) return
            val radius = rect.width() * 0.225f
            clipPath.reset()
            clipPath.addRoundRect(rect, radius, radius, Path.Direction.CW)

            if (bitmap != null) {
                canvas.save()
                canvas.clipPath(clipPath)
                val src = centerCropSource(bitmap, rect.width() / rect.height())
                canvas.drawBitmap(bitmap, src, bounds, paint)
                canvas.restore()
                return
            }

            val backgroundTop = topColor ?: fallbackBackground
            val backgroundBottom = bottomColor ?: backgroundTop
            paint.shader = if (backgroundTop != backgroundBottom) {
                LinearGradient(0f, rect.top, 0f, rect.bottom, backgroundTop, backgroundBottom, Shader.TileMode.CLAMP)
            } else {
                null
            }
            paint.color = backgroundTop
            canvas.drawRoundRect(rect, radius, radius, paint)
            paint.shader = null

            glyph?.let { icon ->
                val ink = projectIconForeground(backgroundTop, backgroundBottom, fallbackInk)
                icon.setTint(ink)
                val glyphSize = (minOf(rect.width(), rect.height()) * 0.62f).toInt()
                val left = bounds.left + ((rect.width() - glyphSize) / 2f).toInt()
                val top = bounds.top + ((rect.height() - glyphSize) / 2f).toInt()
                icon.bounds = Rect(left, top, left + glyphSize, top + glyphSize)
                icon.draw(canvas)
            }

            if (needsProjectIconStroke(backgroundTop, backgroundBottom, hostColor)) {
                strokePaint.strokeWidth = maxOf(1f, rect.width() / 62f)
                strokePaint.color = if (relativeLuminance(averageColor(backgroundTop, backgroundBottom)) > 0.55) {
                    Color.argb(58, 0, 0, 0)
                } else {
                    Color.argb(82, 255, 255, 255)
                }
                val inset = strokePaint.strokeWidth / 2f
                canvas.drawRoundRect(
                    RectF(rect.left + inset, rect.top + inset, rect.right - inset, rect.bottom - inset),
                    radius,
                    radius,
                    strokePaint
                )
            }
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
            strokePaint.alpha = alpha
            glyph?.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
            strokePaint.colorFilter = colorFilter
            glyph?.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Android API")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT

        private fun centerCropSource(bitmap: Bitmap, targetRatio: Float): Rect {
            val bitmapRatio = bitmap.width.toFloat() / bitmap.height.toFloat()
            return if (bitmapRatio > targetRatio) {
                val width = (bitmap.height * targetRatio).toInt().coerceAtLeast(1)
                val left = (bitmap.width - width) / 2
                Rect(left, 0, left + width, bitmap.height)
            } else {
                val height = (bitmap.width / targetRatio).toInt().coerceAtLeast(1)
                val top = (bitmap.height - height) / 2
                Rect(0, top, bitmap.width, top + height)
            }
        }

        private fun projectIconForeground(top: Int, bottom: Int, fallbackInk: Int): Int {
            val base = averageColor(top, bottom)
            if (isNearWhiteNeutral(base)) return INK
            val hsv = FloatArray(3)
            Color.colorToHSV(base, hsv)
            val candidates = mutableListOf<Int>()
            if (hsv[1] > 0.16f) {
                candidates.add(Color.HSVToColor(floatArrayOf((hsv[0] + 180f) % 360f, maxOf(0.58f, hsv[1]), 0.42f)))
                candidates.add(Color.HSVToColor(floatArrayOf((hsv[0] + 150f) % 360f, maxOf(0.52f, hsv[1]), 0.36f)))
                candidates.add(Color.HSVToColor(floatArrayOf((hsv[0] + 210f) % 360f, maxOf(0.52f, hsv[1]), 0.36f)))
            }
            candidates.add(Color.BLACK)
            candidates.add(Color.WHITE)
            candidates.add(fallbackInk)
            return candidates.maxByOrNull { contrastRatio(it, base) } ?: fallbackInk
        }

        private fun isNearWhiteNeutral(color: Int): Boolean {
            val red = Color.red(color)
            val green = Color.green(color)
            val blue = Color.blue(color)
            return red > 238 && green > 238 && blue > 238 &&
                maxOf(red, green, blue) - minOf(red, green, blue) < 14
        }

        private fun needsProjectIconStroke(top: Int, bottom: Int, hostColor: Int): Boolean {
            val background = averageColor(top, bottom)
            return colorDistance(background, hostColor) < 42.0 || contrastRatio(background, hostColor) < 1.22
        }

        private fun averageColor(first: Int, second: Int): Int {
            return Color.rgb(
                (Color.red(first) + Color.red(second)) / 2,
                (Color.green(first) + Color.green(second)) / 2,
                (Color.blue(first) + Color.blue(second)) / 2
            )
        }

        private fun colorDistance(first: Int, second: Int): Double {
            val red = Color.red(first) - Color.red(second)
            val green = Color.green(first) - Color.green(second)
            val blue = Color.blue(first) - Color.blue(second)
            return kotlin.math.sqrt((red * red + green * green + blue * blue).toDouble())
        }

        private fun contrastRatio(first: Int, second: Int): Double {
            val a = relativeLuminance(first)
            val b = relativeLuminance(second)
            val lighter = maxOf(a, b)
            val darker = minOf(a, b)
            return (lighter + 0.05) / (darker + 0.05)
        }

        private fun relativeLuminance(color: Int): Double {
            fun channel(value: Int): Double {
                val normalized = value / 255.0
                return if (normalized <= 0.03928) normalized / 12.92 else Math.pow((normalized + 0.055) / 1.055, 2.4)
            }
            return channel(Color.red(color)) * 0.2126 +
                channel(Color.green(color)) * 0.7152 +
                channel(Color.blue(color)) * 0.0722
        }
    }

    private class NativeFileKindDrawable(
        private val glyph: Drawable?,
        private val fillColor: Int,
        private val tintColor: Int
    ) : Drawable() {
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        override fun draw(canvas: Canvas) {
            val rect = RectF(bounds)
            if (rect.width() <= 0f || rect.height() <= 0f) return
            paint.color = fillColor
            canvas.drawRoundRect(rect, rect.width() * 0.22f, rect.height() * 0.22f, paint)
            glyph?.let { icon ->
                icon.setTint(tintColor)
                val glyphSize = (minOf(rect.width(), rect.height()) * 0.56f).toInt()
                val left = bounds.left + ((rect.width() - glyphSize) / 2f).toInt()
                val top = bounds.top + ((rect.height() - glyphSize) / 2f).toInt()
                icon.bounds = Rect(left, top, left + glyphSize, top + glyphSize)
                icon.draw(canvas)
            }
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
            glyph?.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
            glyph?.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }

    private fun actionButtonBackground(): RippleDrawable {
        return coloredActionButtonBackground(ACCENT_SKY)
    }

    private fun coloredActionButtonBackground(fillColor: Int): RippleDrawable {
        return RippleDrawable(
            ColorStateList.valueOf(RIPPLE),
            AppActionButtonDrawable(
                fillColor = fillColor,
                topGlowStart = SKY_TOP_GLOW_START,
                topGlowEnd = SKY_TOP_GLOW_END,
                innerShadowColor = SKY_INNER_SHADOW,
                dropShadowColor = ACTION_DROP_SHADOW,
                cornerRadius = dp(16).toFloat(),
                innerShadowHeight = dp(4).toFloat(),
                dropShadowOffset = dp(3).toFloat()
            ),
            roundedDrawable(Color.WHITE, dp(16).toFloat())
        )
    }

    private class AppActionButtonDrawable(
        private val fillColor: Int,
        private val topGlowStart: Int,
        private val topGlowEnd: Int,
        private val innerShadowColor: Int,
        private val dropShadowColor: Int,
        private val cornerRadius: Float,
        private val innerShadowHeight: Float,
        private val dropShadowOffset: Float
    ) : Drawable() {
        private val rect = RectF()
        private val shadowRect = RectF()
        private val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        override fun draw(canvas: Canvas) {
            rect.set(bounds.left.toFloat(), bounds.top.toFloat(), bounds.right.toFloat(), bounds.bottom - dropShadowOffset)
            shadowRect.set(rect)
            shadowRect.offset(0f, dropShadowOffset)

            paint.shader = null
            paint.color = dropShadowColor
            canvas.drawRoundRect(shadowRect, cornerRadius, cornerRadius, paint)

            paint.shader = null
            paint.color = fillColor
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, paint)

            paint.shader = LinearGradient(
                0f,
                rect.top,
                0f,
                rect.bottom,
                topGlowStart,
                topGlowEnd,
                Shader.TileMode.CLAMP
            )
            canvas.drawRoundRect(rect, cornerRadius, cornerRadius, paint)

            paint.shader = null
            paint.color = innerShadowColor
            val outerPath = Path().apply {
                addRoundRect(rect, cornerRadius, cornerRadius, Path.Direction.CW)
            }
            val liftedRect = RectF(rect).apply {
                offset(0f, -innerShadowHeight)
            }
            val liftedPath = Path().apply {
                addRoundRect(liftedRect, cornerRadius, cornerRadius, Path.Direction.CW)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                outerPath.op(liftedPath, Path.Op.DIFFERENCE)
                canvas.drawPath(outerPath, paint)
            } else {
                val band = RectF(rect.left, rect.bottom - innerShadowHeight, rect.right, rect.bottom)
                canvas.drawRoundRect(band, cornerRadius, cornerRadius, paint)
            }
        }

        override fun setAlpha(alpha: Int) {
            paint.alpha = alpha
        }

        override fun setColorFilter(colorFilter: ColorFilter?) {
            paint.colorFilter = colorFilter
        }

        @Deprecated("Deprecated in Java")
        override fun getOpacity(): Int = PixelFormat.TRANSLUCENT
    }
}
