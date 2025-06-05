from django.shortcuts import render
from .getS3Obj import download_s3_object
from django.http import HttpResponse
import os

def hello(request):
  msg = os.environ.get('WELCOME_MESSAGE', 'Hello, World!')
  print(f"Message from environment: {msg}")
  return render(request, 'hello.html', {'message': msg})
  
  
def download_file_view(request):
  bucket = 'test-django-irsa-testing'
  key = 'ubuntu-logo.png'
  local_file = '/tmp/file.jpg'

  result = download_s3_object(bucket, key, local_file)
  if result is True:
      with open(local_file, 'rb') as f:
          return HttpResponse(f.read(), content_type='image/jpeg')
  else:
      return HttpResponse(f"S3 download failed:\n{result}", status=500)