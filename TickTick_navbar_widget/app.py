from flask import Flask, request

app = Flask(__name__)

@app.route('/')
def oauth_callback():
    code = request.args.get('code')
    return f"Authorization Code: {code}"

if __name__ == '__main__':
    app.run(port=8080)