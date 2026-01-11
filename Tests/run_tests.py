import os
import subprocess
import sys

def run_tests():
    test_dir = "Tests"
    print(f"--- Desolate Lootcouncil Test Runner ---")
    
    test_files = []
    # Walk directory to find all _Test.lua files
    for root, dirs, files in os.walk(test_dir):
        for file in files:
            if file.endswith("_Test.lua"):
                test_files.append(os.path.join(root, file))
    
    if not test_files:
        print("No test files found in Tests/ directory.")
        return

    failed = False
    
    for f in test_files:
        print(f"\n[RUN] {f}...")
        try:
            # Execute lua file
            subprocess.check_call(["lua", f], shell=True)
            print(f"[PASS] {f}")
        except FileNotFoundError:
             print("CRITICAL ERROR: 'lua' interpreter not found in system PATH.")
             print("Please install Lua 5.1+ to run tests.")
             sys.exit(1)
        except subprocess.CalledProcessError:
             print(f"[FAIL] {f}")
             failed = True
        except Exception as e:
            print(f"[ERR] Failed to execute {f}: {e}")
            failed = True

    print("\n----------------------------------------")
    if failed:
        print("SOME TESTS FAILED.")
        sys.exit(1)
    else:
        print("ALL TESTS PASSED.")
        sys.exit(0)

if __name__ == "__main__":
    run_tests()
