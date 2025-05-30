// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title StudentPerformancePrediction
 * @dev Smart contract for predicting and tracking student performance on blockchain
 * @author Student Performance Prediction Team
 */
contract StudentPerformancePrediction {
    
    // Constants for better gas optimization
    uint256 private constant MAX_GRADE = 100;
    uint256 private constant MAX_PERCENTAGE = 100;
    uint256 private constant MAX_STUDY_HOURS = 40;
    uint256 private constant GRADE_WEIGHT = 50;
    uint256 private constant ATTENDANCE_WEIGHT = 30;
    uint256 private constant STUDY_HOURS_WEIGHT = 20;
    
    // Owner for access control
    address public owner;
    
    // Structure to represent a student's academic data
    struct Student {
        uint256 studentId;
        string name;
        uint256[] grades;
        uint256 attendancePercentage;
        uint256 studyHours;
        uint256 predictedScore;
        bool isActive;
        uint256 timestamp;
        address registeredBy; // Track who registered the student
    }
    
    // Structure for performance metrics
    struct PerformanceMetrics {
        uint256 averageGrade;
        uint256 improvementRate;
        bytes32 performanceCategory; // Using bytes32 instead of string for gas optimization
        uint256 confidenceScore; // Prediction confidence (0-100)
        uint256 lastUpdated;
    }
    
    // Performance categories as bytes32 constants
    bytes32 private constant EXCELLENT = keccak256("Excellent");
    bytes32 private constant GOOD = keccak256("Good");
    bytes32 private constant AVERAGE = keccak256("Average");
    bytes32 private constant NEEDS_IMPROVEMENT = keccak256("Needs Improvement");
    
    // Mapping from student ID to student data
    mapping(uint256 => Student) public students;
    
    // Mapping from student ID to performance metrics
    mapping(uint256 => PerformanceMetrics) public performanceMetrics;
    
    // Array to keep track of all student IDs
    uint256[] public studentIds;
    
    // Mapping to track authorized users (teachers/admins)
    mapping(address => bool) public authorizedUsers;
    
    // Events
    event StudentRegistered(uint256 indexed studentId, string name, address indexed registeredBy);
    event GradeAdded(uint256 indexed studentId, uint256 grade, address indexed addedBy);
    event PerformancePredicted(uint256 indexed studentId, uint256 predictedScore, bytes32 category);
    event AttendanceUpdated(uint256 indexed studentId, uint256 attendancePercentage, address indexed updatedBy);
    event UserAuthorized(address indexed user, address indexed authorizedBy);
    event UserDeauthorized(address indexed user, address indexed deauthorizedBy);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }
    
    modifier onlyAuthorized() {
        require(authorizedUsers[msg.sender] || msg.sender == owner, "Not authorized to perform this action");
        _;
    }
    
    modifier studentExists(uint256 _studentId) {
        require(students[_studentId].isActive, "Student does not exist or is inactive");
        _;
    }
    
    modifier validGrade(uint256 _grade) {
        require(_grade <= MAX_GRADE, "Grade must be between 0 and 100");
        _;
    }
    
    modifier validPercentage(uint256 _percentage) {
        require(_percentage <= MAX_PERCENTAGE, "Percentage must be between 0 and 100");
        _;
    }
    
    modifier validStudentId(uint256 _studentId) {
        require(_studentId > 0, "Student ID must be greater than 0");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        authorizedUsers[msg.sender] = true;
    }
    
    /**
     * @dev Authorize a user to interact with the contract
     * @param _user Address to authorize
     */
    function authorizeUser(address _user) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(!authorizedUsers[_user], "User already authorized");
        
        authorizedUsers[_user] = true;
        emit UserAuthorized(_user, msg.sender);
    }
    
    /**
     * @dev Deauthorize a user
     * @param _user Address to deauthorize
     */
    function deauthorizeUser(address _user) external onlyOwner {
        require(_user != owner, "Cannot deauthorize owner");
        require(authorizedUsers[_user], "User not authorized");
        
        authorizedUsers[_user] = false;
        emit UserDeauthorized(_user, msg.sender);
    }
    
    /**
     * @dev Register a new student in the system
     * @param _studentId Unique identifier for the student
     * @param _name Name of the student
     * @param _attendancePercentage Initial attendance percentage
     * @param _studyHours Weekly study hours
     */
    function registerStudent(
        uint256 _studentId,
        string calldata _name,
        uint256 _attendancePercentage,
        uint256 _studyHours
    ) external 
        onlyAuthorized 
        validStudentId(_studentId)
        validPercentage(_attendancePercentage) 
    {
        require(!students[_studentId].isActive, "Student already exists");
        require(bytes(_name).length > 0 && bytes(_name).length <= 100, "Invalid name length");
        require(_studyHours <= 168, "Study hours cannot exceed hours in a week"); // 168 hours in a week
        
        students[_studentId] = Student({
            studentId: _studentId,
            name: _name,
            grades: new uint256[](0),
            attendancePercentage: _attendancePercentage,
            studyHours: _studyHours,
            predictedScore: 0,
            isActive: true,
            timestamp: block.timestamp,
            registeredBy: msg.sender
        });
        
        studentIds.push(_studentId);
        
        emit StudentRegistered(_studentId, _name, msg.sender);
    }
    
    /**
     * @dev Add a grade for a student and update performance metrics
     * @param _studentId ID of the student
     * @param _grade Grade to be added (0-100)
     */
    function addGrade(uint256 _studentId, uint256 _grade) 
        external 
        onlyAuthorized
        studentExists(_studentId) 
        validGrade(_grade) 
    {
        students[_studentId].grades.push(_grade);
        _updatePerformanceMetrics(_studentId);
        
        emit GradeAdded(_studentId, _grade, msg.sender);
    }
    
    /**
     * @dev Add multiple grades for a student (gas efficient for bulk operations)
     * @param _studentId ID of the student
     * @param _grades Array of grades to be added
     */
    function addMultipleGrades(uint256 _studentId, uint256[] calldata _grades) 
        external 
        onlyAuthorized
        studentExists(_studentId) 
    {
        require(_grades.length > 0 && _grades.length <= 50, "Invalid grades array length");
        
        for (uint256 i = 0; i < _grades.length; i++) {
            require(_grades[i] <= MAX_GRADE, "Invalid grade value");
            students[_studentId].grades.push(_grades[i]);
        }
        
        _updatePerformanceMetrics(_studentId);
        
        // Emit event for the batch operation
        for (uint256 i = 0; i < _grades.length; i++) {
            emit GradeAdded(_studentId, _grades[i], msg.sender);
        }
    }
    
    /**
     * @dev Predict student performance based on historical data and current metrics
     * @param _studentId ID of the student
     * @return predictedScore The predicted performance score
     * @return category Performance category as bytes32
     * @return confidence Confidence level of the prediction
     */
    function predictPerformance(uint256 _studentId) 
        external 
        onlyAuthorized
        studentExists(_studentId) 
        returns (uint256 predictedScore, bytes32 category, uint256 confidence) 
    {
        Student storage student = students[_studentId];
        require(student.grades.length > 0, "No grades available for prediction");
        
        // Calculate average grade with overflow protection
        uint256 totalGrades = 0;
        uint256 gradesLength = student.grades.length;
        
        for (uint256 i = 0; i < gradesLength; i++) {
            totalGrades += student.grades[i];
        }
        uint256 averageGrade = totalGrades / gradesLength;
        
        // Normalize study hours with bounds checking
        uint256 normalizedStudyHours = student.studyHours > MAX_STUDY_HOURS ? 
            MAX_PERCENTAGE : (student.studyHours * MAX_PERCENTAGE) / MAX_STUDY_HOURS;
        
        // Calculate predicted score using weighted average with overflow protection
        uint256 weightedSum = (averageGrade * GRADE_WEIGHT) +
                             (student.attendancePercentage * ATTENDANCE_WEIGHT) +
                             (normalizedStudyHours * STUDY_HOURS_WEIGHT);
        
        predictedScore = weightedSum / 100;
        
        // Ensure predicted score doesn't exceed maximum
        if (predictedScore > MAX_GRADE) {
            predictedScore = MAX_GRADE;
        }
        
        // Determine performance category and confidence
        if (predictedScore >= 85) {
            category = EXCELLENT;
            confidence = 90;
        } else if (predictedScore >= 75) {
            category = GOOD;
            confidence = 85;
        } else if (predictedScore >= 60) {
            category = AVERAGE;
            confidence = 80;
        } else {
            category = NEEDS_IMPROVEMENT;
            confidence = 75;
        }
        
        // Update student's predicted score
        student.predictedScore = predictedScore;
        
        // Update performance metrics
        performanceMetrics[_studentId] = PerformanceMetrics({
            averageGrade: averageGrade,
            improvementRate: _calculateImprovementRate(_studentId),
            performanceCategory: category,
            confidenceScore: confidence,
            lastUpdated: block.timestamp
        });
        
        emit PerformancePredicted(_studentId, predictedScore, category);
        
        return (predictedScore, category, confidence);
    }
    
    /**
     * @dev Update student's attendance percentage
     * @param _studentId ID of the student
     * @param _attendancePercentage New attendance percentage
     */
    function updateAttendance(uint256 _studentId, uint256 _attendancePercentage) 
        external 
        onlyAuthorized
        studentExists(_studentId) 
        validPercentage(_attendancePercentage) 
    {
        students[_studentId].attendancePercentage = _attendancePercentage;
        
        emit AttendanceUpdated(_studentId, _attendancePercentage, msg.sender);
    }
    
    /**
     * @dev Update student's study hours
     * @param _studentId ID of the student
     * @param _studyHours New weekly study hours
     */
    function updateStudyHours(uint256 _studentId, uint256 _studyHours) 
        external 
        onlyAuthorized
        studentExists(_studentId) 
    {
        require(_studyHours <= 168, "Study hours cannot exceed hours in a week");
        students[_studentId].studyHours = _studyHours;
    }
    
    /**
     * @dev Deactivate a student (soft delete)
     * @param _studentId ID of the student
     */
    function deactivateStudent(uint256 _studentId) 
        external 
        onlyAuthorized
        studentExists(_studentId) 
    {
        students[_studentId].isActive = false;
    }
    
    /**
     * @dev Get student information
     * @param _studentId ID of the student
     * @return name Name of the student
     * @return grades Array of student's grades
     * @return attendancePercentage Student's attendance percentage
     * @return studyHours Student's weekly study hours
     * @return predictedScore Student's predicted performance score
     * @return timestamp Registration timestamp
     */
    function getStudent(uint256 _studentId) 
        external 
        view 
        studentExists(_studentId) 
        returns (
            string memory name,
            uint256[] memory grades,
            uint256 attendancePercentage,
            uint256 studyHours,
            uint256 predictedScore,
            uint256 timestamp
        ) 
    {
        Student memory student = students[_studentId];
        return (
            student.name,
            student.grades,
            student.attendancePercentage,
            student.studyHours,
            student.predictedScore,
            student.timestamp
        );
    }
    
    /**
     * @dev Get performance metrics for a student
     * @param _studentId ID of the student
     * @return averageGrade Average grade of the student
     * @return improvementRate Improvement rate percentage
     * @return performanceCategory Performance category as bytes32
     * @return confidenceScore Confidence score of the prediction
     * @return lastUpdated Timestamp of last update
     */
    function getPerformanceMetrics(uint256 _studentId) 
        external 
        view 
        studentExists(_studentId) 
        returns (
            uint256 averageGrade,
            uint256 improvementRate,
            bytes32 performanceCategory,
            uint256 confidenceScore,
            uint256 lastUpdated
        ) 
    {
        PerformanceMetrics memory metrics = performanceMetrics[_studentId];
        return (
            metrics.averageGrade,
            metrics.improvementRate,
            metrics.performanceCategory,
            metrics.confidenceScore,
            metrics.lastUpdated
        );
    }
    
    /**
     * @dev Convert bytes32 category to string for display purposes
     * @param _category Performance category as bytes32
     * @return categoryString Category as string
     */
    function categoryToString(bytes32 _category) external pure returns (string memory) {
        if (_category == EXCELLENT) return "Excellent";
        if (_category == GOOD) return "Good";
        if (_category == AVERAGE) return "Average";
        if (_category == NEEDS_IMPROVEMENT) return "Needs Improvement";
        return "Unknown";
    }
    
    /**
     * @dev Get total number of registered students
     * @return totalCount Total count of students
     */
    function getTotalStudents() external view returns (uint256) {
        return studentIds.length;
    }
    
    /**
     * @dev Get all student IDs (paginated to avoid gas issues)
     * @param _offset Starting index
     * @param _limit Maximum number of results
     * @return studentIdArray Array of student IDs
     */
    function getStudentIds(uint256 _offset, uint256 _limit) 
        external 
        view 
        returns (uint256[] memory) 
    {
        require(_limit > 0 && _limit <= 100, "Invalid limit");
        require(_offset < studentIds.length, "Offset out of bounds");
        
        uint256 end = _offset + _limit;
        if (end > studentIds.length) {
            end = studentIds.length;
        }
        
        uint256[] memory result = new uint256[](end - _offset);
        for (uint256 i = _offset; i < end; i++) {
            result[i - _offset] = studentIds[i];
        }
        
        return result;
    }
    
    // Internal functions
    
    /**
     * @dev Update performance metrics for a student
     * @param _studentId ID of the student
     */
    function _updatePerformanceMetrics(uint256 _studentId) internal {
        Student storage student = students[_studentId];
        uint256 gradesLength = student.grades.length;
        
        if (gradesLength == 0) return;
        
        uint256 totalGrades = 0;
        for (uint256 i = 0; i < gradesLength; i++) {
            totalGrades += student.grades[i];
        }
        
        performanceMetrics[_studentId].averageGrade = totalGrades / gradesLength;
        performanceMetrics[_studentId].improvementRate = _calculateImprovementRate(_studentId);
        performanceMetrics[_studentId].lastUpdated = block.timestamp;
    }
    
    /**
     * @dev Calculate improvement rate based on grade progression
     * @param _studentId ID of the student
     * @return improvementRate Improvement rate percentage
     */
    function _calculateImprovementRate(uint256 _studentId) internal view returns (uint256) {
        Student storage student = students[_studentId];
        uint256 gradesLength = student.grades.length;
        
        if (gradesLength < 2) return 0;
        
        uint256 midPoint = gradesLength / 2;
        if (midPoint == 0) return 0;
        
        uint256 firstHalf = 0;
        uint256 secondHalf = 0;
        
        // Calculate average of first half
        for (uint256 i = 0; i < midPoint; i++) {
            firstHalf += student.grades[i];
        }
        firstHalf = firstHalf / midPoint;
        
        // Calculate average of second half
        uint256 secondHalfLength = gradesLength - midPoint;
        for (uint256 i = midPoint; i < gradesLength; i++) {
            secondHalf += student.grades[i];
        }
        secondHalf = secondHalf / secondHalfLength;
        
        // Calculate improvement rate with safety checks
        if (firstHalf == 0 || secondHalf < firstHalf) {
            return 0; // No improvement or decline
        }
        
        // Prevent overflow in multiplication
        uint256 improvement = secondHalf - firstHalf;
        if (improvement > type(uint256).max / 100) {
            return 100; // Cap at 100% improvement to prevent overflow
        }
        
        return (improvement * 100) / firstHalf;
    }
}
