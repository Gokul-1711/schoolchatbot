from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import json
import os
import openai
from dotenv import load_dotenv
import logging
from datetime import datetime
from typing import Dict, List
import traceback

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler('app.log')
    ]
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CORS(app, resources={r"/api/": {"origins": ""}})

# Load environment variables
load_dotenv()
OPENAI_API_KEY = os.getenv('OPENAI_API_KEY')
if not OPENAI_API_KEY:
    raise ValueError("OPENAI_API_KEY not found in environment variables")
openai.api_key = OPENAI_API_KEY

class ConversationMemory:
    def __init__(self):
        self.conversations = {}
        self.user_data = {}
        self.max_history = 50
    
    def add_message(self, session_id: str, role: str, content: str):
        if session_id not in self.conversations:
            self.conversations[session_id] = []
        message = {
            'role': role,
            'content': content,
            'timestamp': datetime.now().isoformat()
        }
        self.conversations[session_id].append(message)
        if len(self.conversations[session_id]) > self.max_history:
            self.conversations[session_id] = self.conversations[session_id][-self.max_history:]
    
    def add_user_data(self, session_id: str, user_data: dict):
        self.user_data[session_id] = user_data

    def get_user_data(self, session_id: str) -> dict:
        return self.user_data.get(session_id, {})
        
    def get_conversation_history(self, session_id: str, max_messages: int = 10) -> List[Dict]:
        if session_id not in self.conversations:
            return []
        return self.conversations[session_id][-max_messages:]
    
    def clear_conversation(self, session_id: str):
        if session_id in self.conversations:
            self.conversations[session_id] = []

memory = ConversationMemory()

def load_curriculum_data():
    possible_paths = [
        os.path.join('assets', 'data', 'chatbot.json'),
        os.path.join(os.path.dirname(__file__), 'chatbot.json'),
        r"D:\StudioProjects\school\assets\data\chatbot.json"
    ]
    
    for json_path in possible_paths:
        try:
            if os.path.exists(json_path):
                with open(json_path, 'r', encoding='utf-8') as f:
                    curriculum_data = json.load(f)
                    logger.info(f"Successfully loaded curriculum data from {json_path}")
                    return curriculum_data
        except Exception as e:
            logger.error(f"Error loading curriculum data from {json_path}: {str(e)}")
            continue
    
    logger.error("Failed to load curriculum data from all possible paths")
    return {}

curriculum_data = load_curriculum_data()

def is_standards_query(query: str) -> bool:
    query_lower = query.lower()
    keywords = [
        'what standards', 'which standards', 'available standards',
        'what classes', 'which classes', 'available classes', 
        'list standards', 'show standards', 'tell me standards',
        'what standard', 'which standard', 'tell me the standards'
        'tell me the curicullum'
    ]
    return any(keyword in query_lower for keyword in keywords)

SUBJECT_ALIASES = {
    'maths': 'Mathematics',
    'math': 'Mathematics',
    'bio': 'Biology',
    'physics': 'Physics',
    'chem': 'Chemistry',
    'cs': 'Computer Science',
    'computers': 'Computer Science',
    'comp': 'Computer Science',
    'informatics': 'Informatics Practices',
    'ip': 'Informatics Practices',
    'business': 'Business Studies',
    'accounts': 'Accountancy',
    'accounting': 'Accountancy',
    'eco': 'Economics',
    'social': 'Social',
    'political science': 'Politics',
    'polsci': 'Politics'
}

def normalize_subject(subject: str) -> str:
    """Convert subject aliases to standard names"""
    if not subject:
        return None
    subject_lower = subject.lower()
    return SUBJECT_ALIASES.get(subject_lower, subject)

def get_standards_response() -> dict:
    standards = sorted(curriculum_data.keys())
    if standards:
        response = "Here are the available standards:\n\n"
        for std in standards:
            response += f"• Standard {std}\n"
        return {
            "response": response,
            "type": "text"
        }
    return {
        "response": "Sorry, no curriculum data is currently available.",
        "type": "text"
    }

def extract_query_info(query: str, session_id: str):
    query_lower = query.lower()
    standard = None
    
    # First check if standard is mentioned in query
    for std in curriculum_data.keys():
        if std.lower() in query_lower:
            standard = std
            break
            
    # If no standard in query, get from user data
    if not standard:
        user_data = memory.get_user_data(session_id)
        standard = user_data.get('standard', '')

    # Find subject
    subjects = set()
    for std_data in curriculum_data.values():
        subjects.update(std_data.keys())
    
    subject = None
    for sub in subjects:
        if sub.lower() in query_lower:
            subject = sub
            break

    return {
        'standard': standard,
        'subject': subject
    }

def is_curriculum_query(query: str, session_id: str) -> bool:
    query_lower = query.lower()
    
    # Add more subject-specific keywords
    curriculum_keywords = [
        'what chapters', 'list chapters', 'show chapters',
        'which chapters', 'chapters in', 'tell me chapters',
        'syllabus', 'curriculum', 'what are the chapters',
        'tell me the chapters', 'chapters', 'chapter',
        'topics', 'what topics', 'subject content',
        'what is in', 'what do we study in'
    ]
    
    # Get user's standard from session
    user_data = memory.get_user_data(session_id)
    user_standard = user_data.get('standard', '')
    
    # Get all possible subjects from curriculum
    all_subjects = set()
    for std_data in curriculum_data.values():
        all_subjects.update(std_data.keys())
    
    # Check for subject mentions more thoroughly
    has_subject_mention = any(
        subject.lower() in query_lower or 
        query_lower.endswith(subject.lower()) or
        query_lower.startswith(subject.lower())
        for subject in all_subjects
    )
    
    has_curriculum_keyword = any(keyword in query_lower for keyword in curriculum_keywords)
    
    # Return true if:
    # 1. Has curriculum keyword and subject mention
    # 2. Just has subject mention in user's standard context
    return (has_curriculum_keyword and has_subject_mention) or (
        has_subject_mention and user_standard
    )

def extract_subject_from_query(query: str) -> str:
    """Extract subject name from query with better matching"""
    query_lower = query.lower()
    
    all_subjects = set()
    for std_data in curriculum_data.values():
        all_subjects.update(std_data.keys())
    
    # Try exact matches first
    for subject in all_subjects:
        if subject.lower() in query_lower:
            return subject
            
    # Try fuzzy matches
    for subject in all_subjects:
        subject_parts = subject.lower().split()
        if any(part in query_lower for part in subject_parts):
            return subject
            
    return None

def extract_query_info(query: str, session_id: str):
    query_lower = query.lower()
    standard = None
    
    # First check if standard is mentioned in query
    for std in curriculum_data.keys():
        if std.lower() in query_lower:
            standard = std
            break
            
    # If no standard in query, get from user data
    if not standard:
        user_data = memory.get_user_data(session_id)
        standard = user_data.get('standard', '')

    # Find subject with better matching
    subject = extract_subject_from_query(query)

    return {
        'standard': standard,
        'subject': subject
    }
def get_chapters_response(standard: str, subject: str) -> str:
    try:
        if standard in curriculum_data and subject in curriculum_data[standard]:
            chapters = curriculum_data[standard][subject]
            chapter_list = '\n'.join([f"• {chapter}" for chapter in chapters['chapters']])
            return f"Here are the chapters for {subject} in Standard {standard}:\n\n{chapter_list}"
        else:
            return f"Sorry, I couldn't find chapter information for {subject} in Standard {standard}."
    except Exception as e:
        logger.error(f"Error getting chapters: {str(e)}")
        return "Sorry, I encountered an error while fetching the chapter information."

        
0
def handle_curriculum_query(query: str, session_id: str) -> dict:
    try:
        query_info = extract_query_info(query, session_id)
        standard = query_info['standard']
        subject = normalize_subject(query_info['subject'])

        # Get user's standard if not specified in query
        if not standard:
            user_data = memory.get_user_data(session_id)
            standard = user_data.get('standard', '')

        if not standard:
            return {
                "response": "Please specify which standard/class you're asking about.",
                "type": "text"
            }

        if not subject:
            # List available subjects for the standard
            if standard in curriculum_data:
                subjects = list(curriculum_data[standard].keys())
                response = {
                    "response": f"Available subjects for Standard {standard}:\n\n" + 
                               "\n".join([f"• {subject}" for subject in subjects]),
                    "type": "text"
                }
            else:
                response = {
                    "response": f"No curriculum data found for Standard {standard}.",
                    "type": "text"
                }
        else:
            if standard in curriculum_data and subject in curriculum_data[standard]:
                response = {
                    "response": get_chapters_response(standard, subject),
                    "type": "text"
                }
            else:
                available_subjects = list(curriculum_data.get(standard, {}).keys())
                response = {
                    "response": f"The subject '{subject}' is not available for Standard {standard}. Available subjects are:\n\n" + 
                               "\n".join([f"• {subj}" for subj in available_subjects]),
                    "type": "text"
                }
                
        memory.add_message(session_id, "assistant", response["response"])
        return response

    except Exception as e:
        logger.error(f"Error: {str(e)}")
        error_response = {
            "response": "Error processing request. Please try again.",
            "type": "text"
        }
        memory.add_message(session_id, "assistant", error_response["response"])
        return error_response
def handle_educational_query(query: str, session_id: str) -> dict:
    try:
        conversation_history = memory.get_conversation_history(session_id)
        user_data = memory.get_user_data(session_id)
        
        system_message = """You are a helpful AI tutor for school students. Use this student information:
        Name: {name}
        Standard: {standard} 
        Stream: {stream}
        
        Focus on:
        - Providing clear, accurate explanations
        - Using age-appropriate language
        - Breaking down complex topics
        - Explaining step-by-step solutions
        - Providing relevant examples
        - Maintaining context from previous messages"""

        messages = [
            {
                "role": "system",
                "content": system_message.format(
                    name=user_data.get('name', 'Student'),
                    standard=user_data.get('standard', 'Unknown'),
                    stream=user_data.get('stream', '')
                )
            }
        ]
        
        for msg in conversation_history:
            messages.append({
                "role": msg["role"],
                "content": msg["content"]
            })
        
        messages.append({
            "role": "user",
            "content": query
        })
        
        response = openai.ChatCompletion.create(
            model="gpt-4",
            messages=messages,
            temperature=0.7,
            max_tokens=800
        )
        
        assistant_response = response.choices[0].message['content']
        memory.add_message(session_id, "assistant", assistant_response)
        
        return {
            "response": assistant_response,
            "type": "text"
        }
    except Exception as e:
        logger.error(f"Error in OpenAI response: {str(e)}")
        error_response = "I encountered an error while processing your question. Please try again."
        memory.add_message(session_id, "assistant", error_response)
        return {
            "response": error_response,
            "type": "text"
        }

@app.route('/api/chat', methods=['POST'])
def chat():
    try:
        data = request.json
        if not data or 'message' not in data:
            return jsonify({"error": "No message provided"}), 400
        
        user_message = data['message'].strip()
        session_id = data.get('session_id', 'default_session')
        
        if not user_message:
            return jsonify({"error": "Empty message"}), 400
        
        logger.info(f"Received message: {user_message} for session: {session_id}")
        memory.add_message(session_id, "user", user_message)
        
        if is_standards_query(user_message):
            logger.info("Processing as standards query")
            response = get_standards_response()
        elif is_curriculum_query(user_message, session_id):
            logger.info("Processing as curriculum query")
            response = handle_curriculum_query(user_message, session_id)
        else:
            logger.info("Processing as educational query")
            response = handle_educational_query(user_message, session_id)

        return jsonify(response)

    except Exception as e:
        logger.error(f"Error in chat endpoint: {str(e)}\n{traceback.format_exc()}")
        return jsonify({"error": "Internal server error"}), 500
@app.route('/api/chat/user', methods=['POST'])
def set_user_data():
    try:
        data = request.json
        session_id = data.get('session_id', 'default_session')
        user_data = {
            'name': data.get('name'),
            'standard': data.get('standard'),
            'stream': data.get('stream')
        }
        memory.add_user_data(session_id, user_data)
        return jsonify({"message": "User data stored successfully"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/api/chat/history', methods=['GET'])
def get_chat_history():
    session_id = request.args.get('session_id', 'default_session')
    history = memory.get_conversation_history(session_id)
    return jsonify({"history": history})

@app.route('/api/chat/clear', methods=['POST'])
def clear_chat():
    session_id = request.json.get('session_id', 'default_session')
    memory.clear_conversation(session_id)
    return jsonify({"message": "Conversation cleared successfully"})

@app.route('/api/curriculum/set', methods=['POST'])
def set_curriculum():
    try:
        global curriculum_data
        curriculum_data = request.json
        return jsonify({"message": "Curriculum data set successfully"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    logger.info("Starting server...")
    app.run(debug=True, host='0.0.0.0', port=5000)
