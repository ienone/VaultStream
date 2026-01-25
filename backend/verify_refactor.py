
import sys
import os
import asyncio

# 添加当前目录到 path
sys.path.append(os.getcwd())

async def verify_imports():
    print("Verifying imports...")
    try:
        from app.utils import canonicalize_url
        print("✅ app.utils imported")
        
        from app.media.processor import store_archive_images_as_webp
        print("✅ app.media.processor imported")
        
        from app.push.telegram import TelegramPushService
        print("✅ app.push.telegram imported")
        
        from app.worker import worker
        print("✅ app.worker imported")
        
        from app.bot.main import VaultStreamBot
        print("✅ app.bot.main imported")
        
        print("\nAll imports successful!")
        return True
    except Exception as e:
        print(f"\n❌ Import failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    if asyncio.run(verify_imports()):
        sys.exit(0)
    else:
        sys.exit(1)
