import sys, asyncio
from playwright.async_api import async_playwright
async def main(urls, wait):
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", headless=False, args=["--disable-blink-features=AutomationControlled"])
        ctx = await b.new_context(locale="en-CA", viewport={"width":1400,"height":1000}, user_agent="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0 Safari/537.36")
        pg = await ctx.new_page()
        for i,u in enumerate(urls):
            try:
                await pg.goto(u, timeout=60000)
                await pg.wait_for_timeout(wait)
                t = await pg.inner_text("body")
            except Exception as e:
                t = "ERR "+str(e)
            print("=====", u); print(t[:int(sys.argv[2]) if len(sys.argv)>2 else 15000])
        await b.close()
urls=open(sys.argv[1]).read().split()
asyncio.run(main(urls, 8000))
