from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.common.action_chains import ActionChains
from selenium.webdriver.common.keys import Keys
import os
import time 
import sys
import getopt

enable_add_member = False
enable_create_project = False
enable_generate_token = False

# Get full command-line arguments
full_cmd_arguments = sys.argv

short_options = "cga"
long_options = ["create-project", "generate-token", "add-member"]

# Keep all but the first
argument_list = full_cmd_arguments[1:]

try:
    arguments, values = getopt.getopt(argument_list, short_options, long_options)
except getopt.error as err:
    # Output error, and return with an error code
    print (str(err))
    sys.exit(2)

# Evaluate given options
for current_argument, current_value in arguments:
    if current_argument in ("-c", "--create-project"):
        print ("Creating Project")
        enable_create_project = True
    elif current_argument in ("-g", "--genenerate-token"):
        print ("Generate API-Token")
        enable_generate_token = True
    elif current_argument in ("-a", "--add-member"):
        print ("Add Member")
        enable_add_member = True

if True not in (enable_add_member, enable_create_project, enable_generate_token):
  print("No argument submitted. Aborting script...")
  sys.exit()

username       = os.environ.get('USERNAME')
password       = os.environ.get('PASSWORD')
submit         = "submit-login"
project        = os.environ.get('PROJECT')
permissions    = os.environ.get('PERMISSIONS') # Valid inputs: "Read" "Read & Write"
member         = os.environ.get('MEMBER')
member_role    = os.environ.get('MEMBER_ROLE') # valid inputs: "admin" "member" "restricted"

# check if USERNAME, PASSWORD or PROJECT exists

if username is None:
  print("No username for Hetzner Login has been set. Aborting script...")
  sys.exit()

if password is None:
  print("No password for Hetzner Login has been set. Aborting script...")
  sys.exit()

if project is None:
  print("No project name has been set. Aborting script...")
  sys.exit()

# assign default permissions to Read & Write if not passed.

permissions = permissions or "Read & Write"

# initialize the Firefox  driver
firefox_options = webdriver.FirefoxOptions()
firefox_options.add_argument('--no-sandbox')
firefox_options.add_argument('--headless')
firefox_options.add_argument('--disable-gpu')
firefox_options.add_argument('--disable-dev-shm-usage')
firefox_options.add_argument("--window-size=1920,1080")
driver = webdriver.Firefox(options=firefox_options)
driver.implicitly_wait(10)

# call Hcloud login page and pass credentials
driver.get("https://console.hetzner.cloud")
driver.find_element(By.ID, "_username").send_keys(username)
driver.find_element(By.ID, "_password").send_keys(password)
driver.find_element(By.ID, submit).click()

# wait the ready state to be complete
time.sleep(1.5)

# check if login has been succesfully
try:
    driver.find_element(By.XPATH, "//hc-app[1]")
except Exception:
    print("Login failed")
    driver.close()
    sys.exit()

# create a new Project
def create_project():

    # check if Project already exists
    project_names = driver.find_elements(By.XPATH, "(//*[contains(@class, 'project-card__name ng-tns')])")
    project_exists = ""
    for i in project_names:
        if project == i.text:
            project_exists = "exists"
            break
    if project_exists == "exists":
      print("Project already exists. Can't create a Project with the same name. Aborting script...")
      driver.close()
      sys.exit()
    
    # create Hetzner project

    new_project = driver.find_element(By.CSS_SELECTOR, "[id^='PAGE_CONTENT-PROJECTS-ADD_PROJECT_BTN']")
    new_project.click()
    time.sleep(1)
    driver.find_element(By.ID, "name").send_keys(project)
    confirm = driver.find_element(By.CSS_SELECTOR, "[id^='PAGE_CONTENT-PROJECTS-CONFIRM-ADD_BTN']")
    confirm.click()

## enter a Hetzner Project
def enter_project():

    project_names = driver.find_elements(By.XPATH, "(//*[contains(@class, 'project-card__name ng-tns')])")
    project_exists = ""

    for i in project_names:
        if project == i.text:
            i.click()
            time.sleep(1)
            project_exists = "exists"
            break
    if project_exists != "exists":
        print("Project not found")
        driver.close()
        sys.exit()


### Member Invitation Management
def send_member_invitation():

    if member is None:
      print("No Member name has been set. Aborting script...")
      driver.close()
      sys.exit()

    if member_role is None:
      print("No Member Role has been set. Aborting script...")
      driver.close()
      sys.exit()

    
    member_config = driver.find_elements(By.XPATH, "(//*[contains(@class, 'ng-star-inserted')])")
    for n in member_config:
        if "ADD MEMBER" == n.text:
            
            n.click()
            time.sleep(1)

            actions = ActionChains(driver)
            actions.send_keys(member)
            actions.send_keys(Keys.TAB)
            
            if member_role == "admin":
                actions.send_keys(Keys.UP)

            if member_role == "restricted":
                actions.send_keys(Keys.DOWN)
            
            actions.send_keys(Keys.ENTER) # lock in member role
            actions.send_keys(Keys.ENTER) # send invitation
            actions.perform()
            time.sleep(1.5)

            result = driver.find_elements(By.XPATH, "(//*[contains(@class, 'notification__message__heading ng-star-inserted')])")
            for r in result:
                if "User could not be invited" in r.text:
                    print(r.text)
                    driver.close()
                    sys.exit()
                elif "invalid input in field 'email'" in r.text:
                    print(r.text)
                    driver.close()
                    sys.exit()

            print("Member ", member, "succesfully created")
            break
## API Token generation
def generate_api_token():

    api_generate = driver.find_elements(By.XPATH, "(//*[contains(@class, 'hc-button ng-tns')])")
    for j in api_generate:
        j.click()
        api_dscr = driver.find_elements(By.XPATH, "(//*[contains(@id, '__hc-field')])")
        for k in api_dscr:
            k.send_keys(project)
            api_read_write = driver.find_elements(By.XPATH, "(//span[contains(@class, 'hc-radio__label')])")
            for l in api_read_write:
                if permissions in l.text:
                    l.click()
            api_generate_token = driver.find_elements(By.XPATH, "(//span[contains(@class, 'ng-star-inserted')])")
            for m in api_generate_token:
                if "GENERATE API TOKEN" in m.text:
                    m.click()
                    time.sleep(1)
            api_token_list = driver.find_elements(By.XPATH, "(//span[contains(@class, 'click-to-copy__content')])")
            for element in api_token_list:
                api_token = element.text
                print("API_TOKEN Succesfully generated:")
                print(api_token)
                f = open("build/apitoken.env", "w")
                f.write("export HCLOUD_TOKEN=" + api_token)
                f.close()
        break


# create a Hetzner Project
if enable_create_project == True:
    create_project()
    print("Project ", project, "succesfully created")


# Add Member to Project
if enable_add_member == True:
    time.sleep(1)
    enter_project()
    project_url = '/'.join(driver.current_url.split("/")[:-1])
    token_url = project_url+"/security/tokens"
    member_url = project_url+"/security/members"

    driver.get(member_url)
    time.sleep(1)
    send_member_invitation()

# Generate Token
if enable_generate_token == True:
    time.sleep(1)
    enter_project()
    project_url = '/'.join(driver.current_url.split("/")[:-1])
    token_url = project_url+"/security/tokens"
    member_url = project_url+"/security/members"

    driver.get(token_url)
    time.sleep(1)
    generate_api_token()

driver.close()