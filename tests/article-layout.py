"""Exercise the shipped HTML, fonts and WK height bridge in real browser engines.

uv run --with playwright python tests/article-layout.py --chromium /path/to/chrome \
    --webkit /path/to/pw_run.sh [--article-html /path/to/canonical.html]
This checks DOM extents, not UIKit safe-area or on-device rendering.
"""
import argparse
import base64
import json
import re
import tempfile
from pathlib import Path

from playwright.sync_api import sync_playwright

root = Path(__file__).resolve().parents[1]
source = (root / "NFBArticleReaderView.m").read_text()


def literal(name):
    return json.loads(re.search(r'NSString \*' + name + r' = @("(?:[^"\\]|\\.)*");', source)[1])


def shell():
    fonts = ""
    for name, weight in [("Regular", 400), ("Bold", 700)]:
        font = base64.b64encode((root / f"Resources/Chirp/Chirp-{name}.otf").read_bytes()).decode()
        fonts += f"@font-face{{font-family:NFBChirp;font-weight:{weight};src:url(data:font/otf;base64,{font})}}"
    scripts = "window.heights=[];window.webkit={messageHandlers:{articleHeight:{postMessage:h=>heights.push(h)}}};"
    scripts += literal("compatibility")
    for name in ["nfb-marked-15.0.12.js", "nfb-article-reader.js"]:
        scripts += "\n" + (root / "Resources" / name).read_text()
    scripts += "\n" + literal("bridge")
    return literal("html").replace("</style>", fonts + "</style>").replace("</body>", "<script>" + scripts + "</script></body>")


measure = """() => {
  const b = document.getElementById('body');
  const walker = document.createTreeWalker(b, NodeFilter.SHOW_TEXT);
  let n, last; while (n=walker.nextNode()) if(n.textContent.trim()) last=n;
  const range=document.createRange(); range.selectNodeContents(last);
  return {height:heights.at(-1), bottom:range.getBoundingClientRect().bottom,
          text:b.textContent, width:document.body.scrollWidth};
}"""


def verify(page, width, scale):
    page.set_viewport_size({"width": width, "height": 32})
    page.evaluate("s=>{document.getElementById('body').style.zoom=s;nfbMeasure()}", scale)
    result = page.evaluate(measure)
    assert result["height"] - result["bottom"] >= 8 * scale, result
    assert result["width"] <= width, result
    # Simulate the host adopting the bridge's height. It must converge, shrink
    # after a shorter article, and never grow from its own viewport height.
    for _ in range(3):
        page.set_viewport_size({"width": width, "height": int(result["height"])})
        page.evaluate("nfbMeasure()")
        next_result = page.evaluate(measure)
        assert abs(next_result["height"] - result["height"]) <= 1, (result, next_result)
        result = next_result
    return result


def run(browser, html_path, canonical):
    page = browser.new_page(viewport={"width": 346, "height": 32}, device_scale_factor=3)
    errors = []
    page.on("pageerror", lambda error: errors.append(str(error)))
    page.goto(html_path.as_uri())
    page.evaluate("document.fonts.ready")
    endings = ["Final descenders: gypqj.", "**Final descenders: gypqj.**", "*Final descenders: gypqj.*",
               "- Final descenders: gypqj.", "> Final descenders: gypqj.", "### Final descenders: gypqj."]
    checks = 0
    for ending in endings:
        article = {"url": "https://example.org/article", "title": "Fixture",
                   "textContent": "\n\n".join(["A long paragraph with **bold** and *italic* text."] * 12) + "\n\n" + ending}
        page.evaluate("a=>nfbRender(a,'')", article)
        for width in [244, 346, 768]:
            for scale in [.85, 1, 1.3]:
                assert "Final descenders" in verify(page, width, scale)["text"]
                checks += 1
    page.evaluate("nfbRender({url:'https://example.org/short',textContent:'Short gypqj.'},'')")
    assert verify(page, 346, 1)["height"] < 100
    # Intrinsic image size changes after load and font changes both remeasure.
    page.route("https://fixture.invalid/image.svg", lambda route: route.fulfill(
        content_type="image/svg+xml", body='<svg xmlns="http://www.w3.org/2000/svg" width="200" height="300"></svg>'))
    page.evaluate("document.getElementById('body').insertAdjacentHTML('afterbegin','<img src=\"https://fixture.invalid/image.svg\">')")
    page.wait_for_function("document.querySelector('img').complete && document.querySelector('img').naturalHeight===300")
    assert verify(page, 346, 1)["height"] >= 330
    page.evaluate("document.getElementById('body').style.fontSize='23px';document.fonts.dispatchEvent(new Event('loadingdone'))")
    verify(page, 346, 1.3)
    if canonical:
        page.evaluate("document.getElementById('body').style.fontSize=''")
        page.evaluate("h=>nfbRender({url:'https://erickrouss.github.io/blog/my-thoughts-on-ai-ai-coding/',title:'My Thoughts On AI & AI Coding'},h)", canonical)
        for width in [244, 346, 768]:
            for scale in [.85, 1, 1.3]:
                result = verify(page, width, scale)
                assert "Back to the desktop" in result["text"]
                checks += 1
    assert not errors, errors
    page.close()
    return checks


parser = argparse.ArgumentParser()
parser.add_argument("--chromium")
parser.add_argument("--webkit")
parser.add_argument("--article-html", type=Path)
args = parser.parse_args()
assert args.chromium or args.webkit, "Provide at least one browser executable"
with tempfile.TemporaryDirectory() as directory, sync_playwright() as p:
    html_path = Path(directory) / "article.html"
    html_path.write_text(shell())
    for engine in ["chromium", "webkit"]:
        executable = getattr(args, engine)
        if not executable:
            continue
        browser = getattr(p, engine).launch(executable_path=executable, headless=True)
        count = run(browser, html_path, args.article_html.read_text() if args.article_html else None)
        browser.close()
        print(f"PASS {engine}: {count} article width/scale/endings, resize convergence, images, fonts, short body")
