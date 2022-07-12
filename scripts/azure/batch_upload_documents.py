import dotenv
import os
import psycopg2
from psycopg2.extras import RealDictCursor
from pdb import set_trace
from rich.console import Console
from rich import print as print
import uuid
from azure.storage.blob import BlobServiceClient, ContentSettings

console = Console()

dotenv.load_dotenv()
connect_str = os.getenv('AZURE_STORAGE_CONNECTION_STRING')
container = os.getenv('AZURE_STORAGE_CONTAINER')

print(os.getenv("AZURE_COMPUTER_VISION_KEY"))

class DB:
  def __init__(self, name):
      self.conn = psycopg2.connect(os.getenv(name))


def upload_doc(file, filename):
  documentID = uuid.uuid4()
  file.filename = str(documentID) + '.' + getExtension(filename)
  blob_service_client = BlobServiceClient.from_connection_string(
      connect_str)
  blob_client = blob_service_client.get_blob_client(
      container=container, blob=file.filename)
  blob_client.upload_blob(
      file, content_settings=ContentSettings(file.content_type))
  pass

if __name__ == '__main__':
    # db = DB("DOCAI_DEV_DB")
    for (root, dirs, files) in os.walk('/Users/sin/rails/DocAI_Backend_Rails/scripts', topdown=True):
      for f in files:
        console.log(os.path.join(root, f))